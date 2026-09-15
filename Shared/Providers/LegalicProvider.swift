import Combine
import Foundation

enum LegalicRemoteCalendarID {
    static let tasks = "legalic-tasks"
    static let deadlines = "legalic-deadlines"
}

/// LEGALIC через курсорный контракт `/sync/v1`: вход по почте и паролю
/// (`grant_type=password`), лента задач и сроков по делам, запись задач обратно.
///
/// Пароль хранится в Keychain и только после того, как сервер подтвердил пару;
/// адрес сервера и почта — в настройках приложения (это не секреты).
@MainActor
final class LegalicProvider: ObservableObject, CalendarProvider {
    let id: ProviderID = .legalic
    let displayName = "LEGALIC"

    static let defaultServer = "legalic.ru"

    /// Варианты горизонта истории в месяцах; `0` — без ограничения.
    static let historyHorizonOptions: [Int] = [3, 12, 36, 0]
    static let defaultHistoryHorizonMonths = 12

    static func historyHorizonTitle(months: Int) -> String {
        switch months {
        case 0: return "всё"
        case 3: return "3 месяца"
        case 12: return "год"
        case 36: return "3 года"
        default: return "\(months) мес."
        }
    }

    /// Версия правил отбора. Смена значения заставляет перечитать ленты с
    /// начала, чтобы локальный набор соответствовал новым правилам.
    private static let feedRulesVersion = 2

    @Published private(set) var status: ProviderStatus = .signedOut
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.isEnabled) }
    }
    /// Разрешить календарю создавать, менять и удалять задачи в LEGALIC.
    /// По умолчанию выключено: календарь — окно в рабочую базу, а не её редактор.
    @Published var allowsWriteBack: Bool {
        didSet { UserDefaults.standard.set(allowsWriteBack, forKey: Keys.allowsWriteBack) }
    }
    @Published var server: String {
        didSet { UserDefaults.standard.set(server, forKey: Keys.server) }
    }
    @Published var login: String {
        didSet { UserDefaults.standard.set(login, forKey: Keys.login) }
    }
    /// Черновик пароля из формы. В Keychain попадает только после успешного входа.
    @Published var password: String
    /// ФИО учётной записи, как её видит сервер.
    @Published private(set) var accountName: String? {
        didSet { UserDefaults.standard.set(accountName, forKey: Keys.accountName) }
    }
    /// Ленты надо перечитать с начала (см. `CalendarProvider.requiresFullResync`).
    @Published private(set) var requiresFullResync: Bool {
        didSet { UserDefaults.standard.set(requiresFullResync, forKey: Keys.requiresFullResync) }
    }
    /// Как далеко в прошлое брать задачи и сроки, в месяцах (`0` — без ограничения).
    /// Лента отдаёт всё без фильтра по датам, поэтому отсекаем на клиенте; правило
    /// применяется и к инкрементам, так что старая задача, поднявшая `usn`, в
    /// календарь не вернётся. Смена горизонта требует перечитать ленту.
    @Published var historyHorizonMonths: Int {
        didSet {
            guard historyHorizonMonths != oldValue else { return }
            UserDefaults.standard.set(historyHorizonMonths, forKey: Keys.historyHorizonMonths)
            requiresFullResync = true
        }
    }

    private let apiClient: LegalicAPIClient

    init(apiClient: LegalicAPIClient = LegalicAPIClient()) {
        self.apiClient = apiClient
        let defaults = UserDefaults.standard
        self.server = defaults.string(forKey: Keys.server).flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultServer
        self.login = defaults.string(forKey: Keys.login) ?? ""
        self.password = KeychainStore.string(service: Keys.keychainService, account: Keys.password) ?? ""
        self.accountName = defaults.string(forKey: Keys.accountName)
        self.allowsWriteBack = defaults.bool(forKey: Keys.allowsWriteBack)
        self.isEnabled = defaults.bool(forKey: Keys.isEnabled)
        self.requiresFullResync = defaults.bool(forKey: Keys.requiresFullResync)
        self.historyHorizonMonths = defaults.object(forKey: Keys.historyHorizonMonths) as? Int ?? Self.defaultHistoryHorizonMonths

        Self.removeLegacyCredentials()
        if defaults.integer(forKey: Keys.feedRulesVersion) != Self.feedRulesVersion {
            requiresFullResync = true
        }

        if hasStoredCredentials {
            status = .signedIn(accountLabel: accountLabel)
        } else {
            isEnabled = false
            status = .signedOut
        }
    }

    /// Пара подтверждена сервером и лежит в Keychain.
    var hasStoredCredentials: Bool {
        !login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !storedPassword.isEmpty
    }

    /// Можно нажимать «Войти»: заполнены сервер, почта и пароль.
    var canSignIn: Bool {
        !server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty
    }

    private var storedPassword: String {
        KeychainStore.string(service: Keys.keychainService, account: Keys.password) ?? ""
    }

    private var accountLabel: String {
        let mail = login.trimmingCharacters(in: .whitespacesAndNewlines)
        if let accountName, !accountName.isEmpty { return "\(accountName) · \(mail)" }
        return mail
    }

    var serverURL: URL {
        get throws { try LegalicAPIClient.serverURL(from: server) }
    }

    /// Начало окна истории: задачи и сроки, закончившиеся раньше, не импортируются.
    /// `nil` — без ограничения.
    var historyHorizon: Date? {
        guard historyHorizonMonths > 0 else { return nil }
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .month, value: -historyHorizonMonths, to: today)
            ?? today.addingTimeInterval(-Double(historyHorizonMonths) * 30 * 86_400)
    }

    /// Перечитать ленты с начала при следующей синхронизации.
    func requestFullResync() {
        requiresFullResync = true
    }

    func fullResyncDidComplete() {
        requiresFullResync = false
        UserDefaults.standard.set(Self.feedRulesVersion, forKey: Keys.feedRulesVersion)
    }

    // MARK: - CalendarProvider

    func signIn() async throws {
        guard canSignIn else { throw ProviderError.missingCredentials(provider: id) }
        status = .syncing
        do {
            let url = try serverURL
            let account = try await apiClient.signIn(server: url, login: login, password: password)
            guard account.isActive else { throw LegalicAPIError.accountDeactivated }
            try KeychainStore.set(password, service: Keys.keychainService, account: Keys.password)
            accountName = account.fullName
            status = .signedIn(accountLabel: accountLabel)
            isEnabled = true
            LegalicLogger.line("вход выполнен: \(account.fullName)")
        } catch {
            status = .error(error.localizedDescription)
            throw error
        }
    }

    func signOut() async {
        await apiClient.invalidateTokens()
        try? KeychainStore.set("", service: Keys.keychainService, account: Keys.password)
        password = ""
        accountName = nil
        isEnabled = false
        status = .signedOut
    }

    func listRemoteCalendars() async throws -> [RemoteCalendar] {
        guard hasStoredCredentials else { throw ProviderError.notAuthorized(provider: id) }
        return [
            RemoteCalendar(
                id: LegalicRemoteCalendarID.tasks,
                providerID: id,
                title: "LEGALIC · Задачи",
                colorHex: nil,
                isWritable: allowsWriteBack
            ),
            RemoteCalendar(
                id: LegalicRemoteCalendarID.deadlines,
                providerID: id,
                title: "LEGALIC · Сроки по делам",
                colorHex: "#E8A24A",
                isWritable: false
            ),
        ]
    }

    /// Курсор ленты — и `pageToken` внутри одного прогона, и `syncToken` между
    /// прогонами: сервер двигает одну и ту же непрозрачную строку.
    func fetchEvents(calendar: RemoteCalendar, request: SyncRequest) async throws -> SyncBatch {
        guard calendar.providerID == id else { throw ProviderError.remoteCalendarNotFound(remoteID: calendar.id) }
        guard hasStoredCredentials else { throw ProviderError.notAuthorized(provider: id) }
        let url = try serverURL
        let credentials = (login: login, password: storedPassword)
        let cursor = request.pageToken ?? request.syncToken
        let kind: SyncBatchKind = request.syncToken == nil ? .fullSnapshot : .incremental
        let horizon = historyHorizon

        do {
            let batch: SyncBatch
            switch calendar.id {
            case LegalicRemoteCalendarID.tasks:
                let page = try await apiClient.fetchFeedPage(
                    server: url, login: credentials.login, password: credentials.password,
                    resource: LegalicTaskMapper.tasksResource, cursor: cursor,
                    decode: { LegalicTaskMapper.taskRecord(from: $0) }
                )
                var upserts: [ParsedRemoteEvent] = []
                var deletes: [DeletedRemoteEvent] = []
                for record in page.items {
                    let ref = RemoteEventRef(providerID: id, remoteCalendarID: calendar.id, remoteEventID: record.guid)
                    if !record.isDeleted,
                       let event = LegalicTaskMapper.remoteEvent(from: record, providerID: id, remoteCalendarID: calendar.id, horizon: horizon) {
                        upserts.append(event)
                    } else {
                        // Удалена, потеряла даты или старее горизонта — в календаре её быть не должно.
                        deletes.append(DeletedRemoteEvent(remoteRef: ref, updatedAt: record.updatedAt))
                    }
                }
                deletes.append(contentsOf: page.revokedGuids.map {
                    DeletedRemoteEvent(
                        remoteRef: RemoteEventRef(providerID: id, remoteCalendarID: calendar.id, remoteEventID: $0),
                        updatedAt: Date()
                    )
                })
                batch = SyncBatch(
                    upserts: upserts,
                    deletes: deletes,
                    nextPageToken: page.hasMore ? page.nextCursor : nil,
                    nextSyncToken: page.nextCursor,
                    kind: kind
                )

            case LegalicRemoteCalendarID.deadlines:
                let page = try await apiClient.fetchFeedPage(
                    server: url, login: credentials.login, password: credentials.password,
                    resource: LegalicTaskMapper.deadlinesResource, cursor: cursor,
                    decode: { LegalicTaskMapper.deadlineRecord(from: $0) }
                )
                var upserts: [ParsedRemoteEvent] = []
                var deletes: [DeletedRemoteEvent] = []
                for record in page.items {
                    let ref = RemoteEventRef(providerID: id, remoteCalendarID: calendar.id, remoteEventID: record.guid)
                    if !record.isDeleted,
                       let event = LegalicTaskMapper.remoteEvent(from: record, providerID: id, remoteCalendarID: calendar.id, horizon: horizon) {
                        upserts.append(event)
                    } else {
                        deletes.append(DeletedRemoteEvent(remoteRef: ref, updatedAt: record.updatedAt))
                    }
                }
                batch = SyncBatch(
                    upserts: upserts,
                    deletes: deletes,
                    nextPageToken: page.hasMore ? page.nextCursor : nil,
                    nextSyncToken: page.nextCursor,
                    kind: kind
                )

            default:
                throw ProviderError.remoteCalendarNotFound(remoteID: calendar.id)
            }
            status = .signedIn(accountLabel: accountLabel)
            return batch
        } catch {
            // Вход остаётся действительным: ошибка синка — не разлогин.
            status = .error(error.localizedDescription)
            throw error
        }
    }

    func proposedRemoteEventID(for localEvent: CalendarEvent) -> String? {
        guard localEvent.externalId == nil else { return nil }
        return LegalicTaskMapper.remoteGuid(for: localEvent)
    }

    func pushUpsert(localEvent: CalendarEvent, to remoteCalendar: RemoteCalendar) async throws -> PushedRemoteEvent {
        guard remoteCalendar.id == LegalicRemoteCalendarID.tasks, allowsWriteBack else {
            throw ProviderError.notImplemented(provider: id, operation: "запись в календарь \(remoteCalendar.title)")
        }
        guard hasStoredCredentials else { throw ProviderError.notAuthorized(provider: id) }
        let url = try serverURL
        let remoteGuid = localEvent.externalId ?? localEvent.pendingCreateRemoteId ?? LegalicTaskMapper.remoteGuid(for: localEvent)
        let baseUsn = localEvent.externalId == nil ? nil : localEvent.externalETag.flatMap(Int.init)
        let body = LegalicTaskMapper.requestBody(for: localEvent, remoteGuid: remoteGuid, baseUsn: baseUsn)
        let result = try await apiClient.save(
            server: url, login: login, password: storedPassword,
            resource: LegalicTaskMapper.tasksResource,
            body: body,
            idempotencyKey: Self.idempotencyKey(for: localEvent),
            decode: { LegalicTaskMapper.taskRecord(from: $0) }
        )
        guard result.status != 409 else { throw ProviderError.preconditionFailed }
        guard let saved = result.item else {
            throw LegalicAPIError.malformedResponse("сервер не вернул сохранённую задачу")
        }
        return PushedRemoteEvent(
            remoteRef: RemoteEventRef(providerID: id, remoteCalendarID: remoteCalendar.id, remoteEventID: saved.guid),
            etag: String(saved.usn),
            updatedAt: saved.updatedAt == .distantPast ? Date() : saved.updatedAt
        )
    }

    func pushDelete(_ ref: RemoteEventRef, etag: String?) async throws {
        guard ref.remoteCalendarID == LegalicRemoteCalendarID.tasks, allowsWriteBack else {
            throw ProviderError.notImplemented(provider: id, operation: "удаление событий")
        }
        guard hasStoredCredentials else { throw ProviderError.notAuthorized(provider: id) }
        let url = try serverURL
        let result = try await apiClient.save(
            server: url, login: login, password: storedPassword,
            resource: LegalicTaskMapper.tasksResource,
            body: LegalicTaskMapper.deletionBody(remoteGuid: ref.remoteEventID, baseUsn: etag.flatMap(Int.init)),
            idempotencyKey: "delete-\(ref.remoteEventID)-\(etag ?? "0")",
            decode: { LegalicTaskMapper.taskRecord(from: $0) }
        )
        if result.status == 409 {
            // Задачу изменили на сервере после того, как мы её удалили локально.
            // Tombstone остаётся: следующий pull принесёт версию сервера, и LWW решит.
            throw ProviderError.preconditionFailed
        }
    }

    // MARK: - Служебное

    /// Ключ идемпотентности: одно и то же локальное состояние → один ключ, чтобы
    /// повтор после обрыва не создал вторую задачу и не упёрся в «base_usn required».
    private static func idempotencyKey(for event: CalendarEvent) -> String {
        let stamp = Int(event.localUpdatedAt.timeIntervalSince1970)
        return "\(event.id.uuidString.lowercased())-\(stamp)"
    }

    /// Ключи интеграции прежней версии (`api_key`/`api_secret`) больше не нужны.
    private static func removeLegacyCredentials() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Keys.legacyCleaned) else { return }
        try? KeychainStore.set("", service: Keys.keychainService, account: "legalic.apiKey")
        try? KeychainStore.set("", service: Keys.keychainService, account: "legalic.apiSecret")
        for key in ["legalic.apiBaseURL", "legalic.tasksListPath", "legalic.syncTasksInVisibleRangeOnly",
                    "legalic.tasksQueryParamFrom", "legalic.tasksQueryParamTo",
                    "legalic.taskSyncMaxPages", "legalic.taskSyncPerPage"] {
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: Keys.legacyCleaned)
    }

    private enum Keys {
        static let keychainService = "com.lawmatic.calendar.legalic"
        static let password = "legalic.password"
        static let isEnabled = "legalic.isEnabled"
        static let allowsWriteBack = "legalic.allowsWriteBack"
        static let server = "legalic.server"
        static let login = "legalic.login"
        static let accountName = "legalic.accountName"
        static let requiresFullResync = "legalic.requiresFullResync"
        static let feedRulesVersion = "legalic.feedRulesVersion"
        static let historyHorizonMonths = "legalic.historyHorizonMonths"
        static let legacyCleaned = "legalic.legacyCredentialsCleaned.v2"
    }
}
