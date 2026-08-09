import Combine
import Foundation

enum LegalicRemoteCalendarID {
    static let tasks = "legalic"
}

@MainActor
final class LegalicProvider: ObservableObject, CalendarProvider {
    let id: ProviderID = .legalic
    let displayName = "LEGALIC"

    @Published private(set) var status: ProviderStatus = .signedOut
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.isEnabled) }
    }
    @Published var apiKey: String {
        didSet {
            try? KeychainStore.set(apiKey, service: Keys.keychainService, account: Keys.apiKey)
            refreshCredentialStatus()
        }
    }
    @Published var apiSecret: String {
        didSet {
            try? KeychainStore.set(apiSecret, service: Keys.keychainService, account: Keys.apiSecret)
            refreshCredentialStatus()
        }
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
            let clamped = max(1, min(taskSyncMaxPages, 2_000))
            if clamped != taskSyncMaxPages { taskSyncMaxPages = clamped; return }
            UserDefaults.standard.set(clamped, forKey: Keys.taskSyncMaxPages)
        }
    }
    @Published var taskSyncPerPage: Int {
        didSet {
            let clamped = max(1, min(taskSyncPerPage, 500))
            if clamped != taskSyncPerPage { taskSyncPerPage = clamped; return }
            UserDefaults.standard.set(clamped, forKey: Keys.taskSyncPerPage)
        }
    }

    private let apiClient: LegalicAPIClient

    init(apiClient: LegalicAPIClient = .shared) {
        self.apiClient = apiClient
        self.isEnabled = UserDefaults.standard.bool(forKey: Keys.isEnabled)
        self.apiKey = KeychainStore.string(service: Keys.keychainService, account: Keys.apiKey) ?? ""
        self.apiSecret = KeychainStore.string(service: Keys.keychainService, account: Keys.apiSecret) ?? ""
        self.apiBaseURL = UserDefaults.standard.string(forKey: Keys.apiBaseURL) ?? "https://legalic.ru"
        self.tasksListPath = UserDefaults.standard.string(forKey: Keys.tasksListPath) ?? "api/v1/task"
        self.syncTasksInVisibleRangeOnly = UserDefaults.standard.bool(forKey: Keys.syncVisibleRange)
        self.tasksQueryParamFrom = UserDefaults.standard.string(forKey: Keys.tasksQueryFrom) ?? "from"
        self.tasksQueryParamTo = UserDefaults.standard.string(forKey: Keys.tasksQueryTo) ?? "to"
        self.taskSyncMaxPages = max(1, UserDefaults.standard.object(forKey: Keys.taskSyncMaxPages) as? Int ?? 5)
        self.taskSyncPerPage = max(1, UserDefaults.standard.object(forKey: Keys.taskSyncPerPage) as? Int ?? 50)
        if !hasCredentials { self.isEnabled = false }
        refreshCredentialStatus()
    }

    var hasCredentials: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func signIn() async throws {
        guard hasCredentials else { throw ProviderError.missingCredentials(provider: id) }
        status = .syncing
        do {
            try await apiClient.validateCredentials(
                baseURL: resolvedBaseURL,
                apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                apiSecret: apiSecret.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            status = .signedIn(accountLabel: "API: \(LegalicLogger.maskedApiKey(apiKey))")
            isEnabled = true
        } catch {
            status = .error(error.localizedDescription)
            throw error
        }
    }

    func signOut() async {
        await apiClient.invalidateToken()
        isEnabled = false
        status = .signedOut
    }

    func listRemoteCalendars() async throws -> [RemoteCalendar] {
        guard hasCredentials else { throw ProviderError.missingCredentials(provider: id) }
        return [
            RemoteCalendar(
                id: LegalicRemoteCalendarID.tasks,
                providerID: id,
                title: displayName,
                colorHex: nil,
                isWritable: false
            ),
        ]
    }

    func fetchEvents(calendar: RemoteCalendar, request: SyncRequest) async throws -> SyncBatch {
        guard calendar.providerID == id else { throw ProviderError.remoteCalendarNotFound(remoteID: calendar.id) }
        guard hasCredentials else { throw ProviderError.missingCredentials(provider: id) }
        let range = syncTasksInVisibleRangeOnly ? request.dateRange : nil
        let tasksURL = tasksFetchURL(visibleDateRange: range)
        status = .syncing
        do {
            let imports = try await apiClient.fetchTasks(
                baseURL: resolvedBaseURL,
                tasksURL: tasksURL,
                apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                apiSecret: apiSecret.trimmingCharacters(in: .whitespacesAndNewlines),
                maxPages: taskSyncMaxPages,
                perPage: taskSyncPerPage
            )
            status = .signedIn(accountLabel: "API: \(LegalicLogger.maskedApiKey(apiKey))")
            let upserts = imports.map { item in
                ParsedRemoteEvent(
                    remoteRef: RemoteEventRef(
                        providerID: id,
                        remoteCalendarID: calendar.id,
                        remoteEventID: item.id
                    ),
                    title: item.title,
                    start: item.startDate,
                    end: item.endDate,
                    isAllDay: item.isAllDay,
                    notes: item.notes,
                    location: "",
                    updatedAt: item.updatedAt,
                    etag: nil
                )
            }
            return SyncBatch(
                upserts: upserts,
                deletes: [],
                nextPageToken: nil,
                nextSyncToken: nil,
                // API может вернуть лишь первые N страниц, поэтому отсутствие
                // задачи в этом ответе нельзя трактовать как удаление.
                kind: .incremental,
                coveredDateRange: range
            )
        } catch {
            status = .error(error.localizedDescription)
            throw error
        }
    }

    func pushUpsert(localEvent: CalendarEvent, to remoteCalendar: RemoteCalendar) async throws -> PushedRemoteEvent {
        throw ProviderError.notImplemented(provider: id, operation: "запись событий")
    }

    func pushDelete(_ ref: RemoteEventRef, etag: String?) async throws {
        throw ProviderError.notImplemented(provider: id, operation: "удаление событий")
    }

    var resolvedBaseURL: URL {
        let value = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: value) ?? URL(string: "https://legalic.ru")!
    }

    func tasksFetchURL(visibleDateRange: ClosedRange<Date>?) -> URL {
        var url = resolvedBaseURL
        for component in tasksListPath.split(separator: "/") where !component.isEmpty {
            url.appendPathComponent(String(component))
        }
        guard let visibleDateRange,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: tasksQueryParamFrom, value: Self.iso8601.string(from: visibleDateRange.lowerBound)))
        items.append(URLQueryItem(name: tasksQueryParamTo, value: Self.iso8601.string(from: visibleDateRange.upperBound)))
        components.queryItems = items
        return components.url ?? url
    }

    private func refreshCredentialStatus() {
        guard !isSyncing else { return }
        status = hasCredentials
            ? .signedIn(accountLabel: "API: \(LegalicLogger.maskedApiKey(apiKey))")
            : .signedOut
    }

    private var isSyncing: Bool {
        if case .syncing = status { return true }
        return false
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private enum Keys {
        static let keychainService = "com.lawmatic.calendar.legalic"
        static let isEnabled = "legalic.isEnabled"
        static let apiKey = "legalic.apiKey"
        static let apiSecret = "legalic.apiSecret"
        static let apiBaseURL = "legalic.apiBaseURL"
        static let tasksListPath = "legalic.tasksListPath"
        static let syncVisibleRange = "legalic.syncTasksInVisibleRangeOnly"
        static let tasksQueryFrom = "legalic.tasksQueryParamFrom"
        static let tasksQueryTo = "legalic.tasksQueryParamTo"
        static let taskSyncMaxPages = "legalic.taskSyncMaxPages"
        static let taskSyncPerPage = "legalic.taskSyncPerPage"
    }
}
