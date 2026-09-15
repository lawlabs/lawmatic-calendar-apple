import Foundation

@MainActor
protocol CalendarProvider: AnyObject {
    var id: ProviderID { get }
    var displayName: String { get }
    var status: ProviderStatus { get }
    var isEnabled: Bool { get set }

    func signIn() async throws
    func signOut() async
    func listRemoteCalendars() async throws -> [RemoteCalendar]
    func fetchEvents(calendar: RemoteCalendar, request: SyncRequest) async throws -> SyncBatch
    func proposedRemoteEventID(for localEvent: CalendarEvent) -> String?
    func pushUpsert(localEvent: CalendarEvent, to remoteCalendar: RemoteCalendar) async throws -> PushedRemoteEvent
    func pushDelete(_ ref: RemoteEventRef, etag: String?) async throws

    /// Провайдер просит перечитать свои ленты с начала (сменились правила
    /// отбора, пользователь нажал «перечитать»). Координатор сбрасывает
    /// курсоры и после успешного полного чтения зовёт `fullResyncDidComplete()`.
    var requiresFullResync: Bool { get }
    func fullResyncDidComplete()
}

extension CalendarProvider {
    func proposedRemoteEventID(for localEvent: CalendarEvent) -> String? { nil }
    var requiresFullResync: Bool { false }
    func fullResyncDidComplete() {}
}

struct RemoteCalendar: Identifiable, Hashable, Sendable {
    let id: String
    let providerID: ProviderID
    let title: String
    let colorHex: String?
    let isWritable: Bool
}

struct RemoteEventRef: Hashable, Codable, Sendable {
    let providerID: ProviderID
    let remoteCalendarID: String
    let remoteEventID: String
}

struct PushedRemoteEvent: Sendable {
    let remoteRef: RemoteEventRef
    let etag: String?
    let updatedAt: Date
}

struct SyncRequest: Sendable {
    let dateRange: ClosedRange<Date>?
    let pageToken: String?
    let syncToken: String?
}

enum SyncBatchKind: Sendable {
    /// Батч является полной выборкой для `SyncRequest.dateRange`.
    case fullSnapshot
    /// Батч содержит только изменения после переданного sync token.
    case incremental
}

struct SyncBatch: Sendable {
    let upserts: [ParsedRemoteEvent]
    let deletes: [DeletedRemoteEvent]
    let nextPageToken: String?
    let nextSyncToken: String?
    let kind: SyncBatchKind
    /// Диапазон, полностью покрытый snapshot-батчем. `nil` означает
    /// неограниченную полную выборку; для incremental-батчей не используется.
    let coveredDateRange: ClosedRange<Date>?

    init(
        upserts: [ParsedRemoteEvent],
        deletes: [DeletedRemoteEvent],
        nextPageToken: String?,
        nextSyncToken: String?,
        kind: SyncBatchKind,
        coveredDateRange: ClosedRange<Date>? = nil
    ) {
        self.upserts = upserts
        self.deletes = deletes
        self.nextPageToken = nextPageToken
        self.nextSyncToken = nextSyncToken
        self.kind = kind
        self.coveredDateRange = coveredDateRange
    }
}

struct ParsedRemoteEvent: Sendable {
    let remoteRef: RemoteEventRef
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let notes: String
    let location: String
    let updatedAt: Date
    let etag: String?
    /// Запись нельзя менять из приложения, даже если календарь writable.
    var isReadOnly: Bool = false
}

struct DeletedRemoteEvent: Sendable {
    let remoteRef: RemoteEventRef
    let updatedAt: Date
}
