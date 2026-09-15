import Foundation

enum FileCalendarStoreError: LocalizedError {
    case appSupportUnavailable
    case failedToCreateDirectory
    /// Файл не прочитался; копия сохранена рядом, чтобы данные не пропали.
    case unreadable(file: String, backup: String, underlying: String)

    var errorDescription: String? {
        switch self {
        case .appSupportUnavailable:
            return "Не удалось получить папку Application Support."
        case .failedToCreateDirectory:
            return "Не удалось создать папку для хранения данных календаря."
        case .unreadable(let file, let backup, let underlying):
            return "Файл \(file) не прочитался (\(underlying)). Его копия сохранена как \(backup); приложение продолжит с пустым списком."
        }
    }
}

/// JSON-хранилище в Application Support.
///
/// Чтение синхронное (выполняется один раз при запуске). Запись — отложенная:
/// значение ставится в очередь на фоновый serial-поток, где кодируется и
/// атомарно пишется на диск. Несколько записей одного файла подряд
/// схлопываются в последнюю, а ошибки приходят через `setWriteErrorHandler`.
/// Так `save*` не держат main actor на encode + I/O.
final class FileCalendarStore: CalendarStore {
    private let baseURL: URL
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    private let writeQueue = DispatchQueue(label: "com.lawmatic.calendar.store.write", qos: .utility)
    private let inFlight = DispatchGroup()
    private let stateLock = NSLock()
    private var generations: [URL: UInt64] = [:]
    private var directoryError: Error?
    private var writeErrorHandler: (@MainActor (Error) -> Void)?

    /// - Parameter baseURL: папка с файлами; по умолчанию — Application Support.
    init(fileManager: FileManager = .default, baseURL: URL? = nil) {
        self.fileManager = fileManager
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .custom { try Self.decodeDateTolerantly($0) }

        if let baseURL {
            self.baseURL = baseURL
        } else if let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            self.baseURL = applicationSupportURL.appendingPathComponent("LawMaticCalendar", isDirectory: true)
        } else {
            self.baseURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("LawMaticCalendar", isDirectory: true)
        }

        do {
            try fileManager.createDirectory(at: self.baseURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            directoryError = FileCalendarStoreError.failedToCreateDirectory
        }
    }

    // MARK: - CalendarStore

    func loadCalendars() throws -> [CalendarItem] {
        try loadArray([CalendarItem].self, from: calendarsURL)
    }

    func saveCalendars(_ calendars: [CalendarItem]) throws {
        try enqueueWrite(calendars, to: calendarsURL)
    }

    func loadEvents() throws -> [CalendarEvent] {
        try loadArray([CalendarEvent].self, from: eventsURL)
    }

    func saveEvents(_ events: [CalendarEvent]) throws {
        try enqueueWrite(events, to: eventsURL)
    }

    func loadPendingDeletions() throws -> [PendingEventDeletion] {
        try loadArray([PendingEventDeletion].self, from: pendingDeletionsURL)
    }

    func savePendingDeletions(_ deletions: [PendingEventDeletion]) throws {
        try enqueueWrite(deletions, to: pendingDeletionsURL)
    }

    func setWriteErrorHandler(_ handler: @escaping @MainActor (Error) -> Void) {
        stateLock.withLock { writeErrorHandler = handler }
    }

    /// Дождаться завершения всех поставленных в очередь записей
    /// (например, перед завершением приложения).
    func waitForPendingWrites(timeout: TimeInterval = 5) {
        _ = inFlight.wait(timeout: .now() + timeout)
    }

    // MARK: - Пути

    private var calendarsURL: URL {
        baseURL.appendingPathComponent("calendars.json")
    }

    private var eventsURL: URL {
        baseURL.appendingPathComponent("events.json")
    }

    private var pendingDeletionsURL: URL {
        baseURL.appendingPathComponent("pending-event-deletions.json")
    }

    // MARK: - Чтение / запись

    private func loadArray<T: Decodable>(_ type: [T].Type, from url: URL) throws -> [T] {
        if let directoryError { throw directoryError }

        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }

        let data = try Data(contentsOf: url)
        do {
            return try decoder.decode([T].self, from: data)
        } catch {
            // Нечитаемый файл нельзя молча заменить пустым состоянием — следующая
            // запись затёрла бы данные. Откладываем копию и только потом сдаёмся.
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backupURL = url.deletingPathExtension().appendingPathExtension("broken-\(stamp).json")
            try? fileManager.copyItem(at: url, to: backupURL)
            throw FileCalendarStoreError.unreadable(
                file: url.lastPathComponent,
                backup: backupURL.lastPathComponent,
                underlying: error.localizedDescription
            )
        }
    }

    /// Даты пишутся как ISO 8601. При чтении терпим то, что сам `ISO8601DateFormatter`
    /// не разбирает (например, отрицательный год из старых импортов): одна кривая
    /// дата не должна делать нечитаемым файл с десятками тысяч событий.
    private static let isoDecoder: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoFractionalDecoder: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func decodeDateTolerantly(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        if let seconds = try? container.decode(Double.self) {
            return Date(timeIntervalSinceReferenceDate: seconds)
        }
        let string = try container.decode(String.self)
        if let date = isoDecoder.date(from: string) ?? isoFractionalDecoder.date(from: string) {
            return date
        }
        // Год вне диапазона формата — считаем дату отсутствующей (начало отсчёта).
        return .distantPast
    }

    private func enqueueWrite<T: Encodable & Sendable>(_ value: T, to url: URL) throws {
        if let directoryError { throw directoryError }

        let generation: UInt64 = stateLock.withLock {
            let next = (generations[url] ?? 0) + 1
            generations[url] = next
            return next
        }

        inFlight.enter()
        writeQueue.async { [self] in
            defer { inFlight.leave() }

            // Пока эта запись ждала очереди, могла прийти более новая версия —
            // тогда писать устаревшую бессмысленно.
            let latest: UInt64 = stateLock.withLock { generations[url] ?? 0 }
            guard generation == latest else { return }

            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(value)
                try data.write(to: url, options: .atomic)
            } catch {
                let handler: (@MainActor (Error) -> Void)? = stateLock.withLock { writeErrorHandler }
                guard let handler else { return }
                Task { @MainActor in handler(error) }
            }
        }
    }
}
