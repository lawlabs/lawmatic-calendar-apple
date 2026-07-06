import Combine
import Foundation

enum LegalicDataMode: String, CaseIterable, Identifiable {
    case localOnly = "Только локальные данные"
    case legalicOnly = "Только Legalic"
    case hybrid = "Гибридный"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .localOnly:
            return "События и справочники берутся только из локального хранилища."
        case .legalicOnly:
            return "Для календаря и связанных данных используется API LEGALIC."
        case .hybrid:
            return "Доступны и локальные данные, и LEGALIC; при выборе из LEGALIC элемент может импортироваться в локальный кэш."
        }
    }
}

@MainActor
final class LegalicService: ObservableObject {
    static let shared = LegalicService()

    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: Keys.apiKey) }
    }

    @Published var apiSecret: String {
        didSet { UserDefaults.standard.set(apiSecret, forKey: Keys.apiSecret) }
    }

    @Published var dataMode: LegalicDataMode {
        didSet { UserDefaults.standard.set(dataMode.rawValue, forKey: Keys.dataMode) }
    }

    @Published var apiBaseURL: String {
        didSet { UserDefaults.standard.set(apiBaseURL, forKey: Keys.apiBaseURL) }
    }

    @Published var tasksListPath: String {
        didSet { UserDefaults.standard.set(tasksListPath, forKey: Keys.tasksListPath) }
    }

    @Published var syncTasksInVisibleRangeOnly: Bool {
        didSet { UserDefaults.standard.set(syncTasksInVisibleRangeOnly, forKey: Keys.syncVisibleRange) }
    }

    @Published var tasksQueryParamFrom: String {
        didSet { UserDefaults.standard.set(tasksQueryParamFrom, forKey: Keys.tasksQueryFrom) }
    }

    @Published var tasksQueryParamTo: String {
        didSet { UserDefaults.standard.set(tasksQueryParamTo, forKey: Keys.tasksQueryTo) }
    }

    @Published var taskSyncMaxPages: Int {
        didSet {
            let value = max(1, min(taskSyncMaxPages, 2000))
            if value != taskSyncMaxPages {
                taskSyncMaxPages = value
                return
            }
            UserDefaults.standard.set(value, forKey: Keys.taskSyncMaxPages)
        }
    }

    @Published var taskSyncPerPage: Int {
        didSet {
            let value = max(1, min(taskSyncPerPage, 500))
            if value != taskSyncPerPage {
                taskSyncPerPage = value
                return
            }
            UserDefaults.standard.set(value, forKey: Keys.taskSyncPerPage)
        }
    }

    private enum Keys {
        static let apiKey = "legalic.apiKey"
        static let apiSecret = "legalic.apiSecret"
        static let dataMode = "legalic.dataMode"
        static let apiBaseURL = "legalic.apiBaseURL"
        static let tasksListPath = "legalic.tasksListPath"
        static let syncVisibleRange = "legalic.syncTasksInVisibleRangeOnly"
        static let tasksQueryFrom = "legalic.tasksQueryParamFrom"
        static let tasksQueryTo = "legalic.tasksQueryParamTo"
        static let taskSyncMaxPages = "legalic.taskSyncMaxPages"
        static let taskSyncPerPage = "legalic.taskSyncPerPage"
    }

    private init() {
        apiKey = UserDefaults.standard.string(forKey: Keys.apiKey) ?? ""
        apiSecret = UserDefaults.standard.string(forKey: Keys.apiSecret) ?? ""
        let rawMode = UserDefaults.standard.string(forKey: Keys.dataMode) ?? LegalicDataMode.localOnly.rawValue
        dataMode = LegalicDataMode(rawValue: rawMode) ?? .localOnly
        apiBaseURL = UserDefaults.standard.string(forKey: Keys.apiBaseURL) ?? "https://legalic.ru"
        tasksListPath = UserDefaults.standard.string(forKey: Keys.tasksListPath) ?? "api/v1/task"
        if UserDefaults.standard.object(forKey: Keys.syncVisibleRange) == nil {
            syncTasksInVisibleRangeOnly = false
        } else {
            syncTasksInVisibleRangeOnly = UserDefaults.standard.bool(forKey: Keys.syncVisibleRange)
        }
        tasksQueryParamFrom = UserDefaults.standard.string(forKey: Keys.tasksQueryFrom) ?? "from"
        tasksQueryParamTo = UserDefaults.standard.string(forKey: Keys.tasksQueryTo) ?? "to"
        if UserDefaults.standard.object(forKey: Keys.taskSyncMaxPages) == nil {
            UserDefaults.standard.set(5, forKey: Keys.taskSyncMaxPages)
        }
        taskSyncMaxPages = max(1, min(UserDefaults.standard.integer(forKey: Keys.taskSyncMaxPages), 2000))
        if UserDefaults.standard.object(forKey: Keys.taskSyncPerPage) == nil {
            UserDefaults.standard.set(50, forKey: Keys.taskSyncPerPage)
        }
        taskSyncPerPage = max(1, min(UserDefaults.standard.integer(forKey: Keys.taskSyncPerPage), 500))
    }

    var resolvedBaseURL: URL {
        var stringValue = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if stringValue.hasSuffix("/") {
            stringValue.removeLast()
        }
        return URL(string: stringValue) ?? URL(string: "https://legalic.ru")!
    }

    func resolvedTasksListURL() -> URL {
        var url = resolvedBaseURL
        for segment in tasksListPath.split(separator: "/") where !segment.isEmpty {
            url = url.appendingPathComponent(String(segment))
        }
        return url
    }

    private static let isoQuery: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func tasksFetchURL(visibleDateRange: ClosedRange<Date>?) -> URL {
        let baseURL = resolvedTasksListURL()
        guard syncTasksInVisibleRangeOnly, let visibleDateRange else {
            return baseURL
        }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: tasksQueryParamFrom, value: Self.isoQuery.string(from: visibleDateRange.lowerBound)))
        items.append(URLQueryItem(name: tasksQueryParamTo, value: Self.isoQuery.string(from: visibleDateRange.upperBound)))
        components.queryItems = items
        return components.url ?? baseURL
    }

    var hasCredentials: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
