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

final class FileCalendarStore: CalendarStore {
    private let baseURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601

        if let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            self.baseURL = applicationSupportURL.appendingPathComponent("LawMaticCalendar", isDirectory: true)
        } else {
            self.baseURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("LawMaticCalendar", isDirectory: true)
        }
    }

    func loadCalendars() throws -> [CalendarItem] {
        try loadArray([CalendarItem].self, from: calendarsURL)
    }

    func saveCalendars(_ calendars: [CalendarItem]) throws {
        try save(calendars, to: calendarsURL)
    }

    func loadEvents() throws -> [CalendarEvent] {
        try loadArray([CalendarEvent].self, from: eventsURL)
    }

    func saveEvents(_ events: [CalendarEvent]) throws {
        try save(events, to: eventsURL)
    }

    private var calendarsURL: URL {
        baseURL.appendingPathComponent("calendars.json")
    }

    private var eventsURL: URL {
        baseURL.appendingPathComponent("events.json")
    }

    private func ensureDirectoryExists() throws {
        if baseURL.path.isEmpty {
            throw FileCalendarStoreError.appSupportUnavailable
        }

        guard !baseURL.path.isEmpty else {
            throw FileCalendarStoreError.failedToCreateDirectory
        }

        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true, attributes: nil)
    }

    private func loadArray<T: Decodable>(_ type: [T].Type, from url: URL) throws -> [T] {
        try ensureDirectoryExists()

        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }

        let data = try Data(contentsOf: url)
        return try decoder.decode([T].self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to url: URL) throws {
        try ensureDirectoryExists()
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }
}
