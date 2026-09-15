import Foundation

enum FileCalendarStoreError: LocalizedError {
    case appSupportUnavailable
    case failedToCreateDirectory

    var errorDescription: String? {
        switch self {
        case .appSupportUnavailable:
            return "Не удалось получить папку Application Support."
        case .failedToCreateDirectory:
            return "Не удалось создать папку для хранения данных календаря."
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

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        if let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            self.baseURL = applicationSupportURL.appendingPathComponent("LawMaticCalendar", isDirectory: true)
        } else {
            self.baseURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("LawMaticCalendar", isDirectory: true)
        }

        do {
            try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true, attributes: nil)
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
        return try decoder.decode([T].self, from: data)
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
