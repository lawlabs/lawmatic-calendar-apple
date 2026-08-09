import XCTest
@testable import LawMaticCalendar

final class CalendarSyncMergerTests: XCTestCase {
    private let calendar = CalendarItem(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Google",
        color: .blue,
        accountName: "Google Calendar",
        externalProvider: .google,
        externalId: "primary",
        isWritable: true
    )

    func testRemoteNewerVersionWinsLWWConflict() throws {
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)
        let local = localEvent(title: "Локальная версия", updatedAt: old, state: .pendingUpload)
        let batch = batch(upserts: [remoteEvent(title: "Удалённая версия", updatedAt: new)])

        let merged = CalendarSyncMerger.merge(batch, into: [local], localCalendar: calendar, dateRange: nil)

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].title, "Удалённая версия")
        XCTAssertEqual(merged[0].syncState, .clean)
        XCTAssertEqual(merged[0].localUpdatedAt, new)
    }

    func testNewerPendingLocalVersionSurvivesRemoteUpsert() throws {
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)
        let local = localEvent(title: "Локальная версия", updatedAt: new, state: .pendingUpload)
        let batch = batch(upserts: [remoteEvent(title: "Старая удалённая", updatedAt: old)])

        let merged = CalendarSyncMerger.merge(batch, into: [local], localCalendar: calendar, dateRange: nil)

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].title, local.title)
        XCTAssertEqual(merged[0].localUpdatedAt, local.localUpdatedAt)
        XCTAssertEqual(merged[0].syncState, .pendingUpload)
        XCTAssertEqual(merged[0].externalETag, "etag-1000.0")
    }

    func testPullLinksServerResultOfRetriedInsertToPendingLocalEvent() throws {
        let localID = UUID()
        var local = localEvent(title: "Создано локально", updatedAt: Date(timeIntervalSince1970: 1_000), state: .pendingUpload)
        local.id = localID
        local.externalId = nil
        local.pendingCreateRemoteId = "client-generated-id"
        var remote = remoteEvent(title: "Создано локально", updatedAt: Date(timeIntervalSince1970: 2_000))
        remote = ParsedRemoteEvent(
            remoteRef: RemoteEventRef(
                providerID: remote.remoteRef.providerID,
                remoteCalendarID: remote.remoteRef.remoteCalendarID,
                remoteEventID: "client-generated-id"
            ),
            title: remote.title,
            start: remote.start,
            end: remote.end,
            isAllDay: remote.isAllDay,
            notes: remote.notes,
            location: remote.location,
            updatedAt: remote.updatedAt,
            etag: remote.etag
        )

        let merged = CalendarSyncMerger.merge(
            batch(upserts: [remote]),
            into: [local],
            localCalendar: calendar,
            dateRange: nil
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].id, localID)
        XCTAssertEqual(merged[0].externalId, "client-generated-id")
        XCTAssertNil(merged[0].pendingCreateRemoteId)
        XCTAssertEqual(merged[0].syncState, .clean)
    }

    func testFullSnapshotRemovesMissingCleanEventButKeepsPendingEvent() throws {
        let clean = localEvent(remoteID: "missing-clean", title: "Clean", updatedAt: .distantPast, state: .clean)
        let pending = localEvent(remoteID: "missing-pending", title: "Pending", updatedAt: Date(), state: .pendingUpload)
        let snapshot = batch(upserts: [], kind: .fullSnapshot)

        let merged = CalendarSyncMerger.merge(snapshot, into: [clean, pending], localCalendar: calendar, dateRange: nil)

        XCTAssertEqual(merged, [pending])
    }

    func testIncrementalBatchDoesNotTreatAbsentEventAsDeleted() throws {
        let clean = localEvent(title: "Existing", updatedAt: .distantPast, state: .clean)
        let delta = batch(upserts: [], kind: .incremental)

        let merged = CalendarSyncMerger.merge(delta, into: [clean], localCalendar: calendar, dateRange: nil)

        XCTAssertEqual(merged, [clean])
    }

    func testFullSnapshotOnlyRemovesMissingEventsInsideCoveredRange() throws {
        let inside = localEvent(remoteID: "inside", title: "Inside", updatedAt: .distantPast, state: .clean)
        var outside = localEvent(remoteID: "outside", title: "Outside", updatedAt: .distantPast, state: .clean)
        outside.startDate = Date(timeIntervalSince1970: 30_000)
        outside.endDate = Date(timeIntervalSince1970: 31_000)
        let coverage = Date(timeIntervalSince1970: 9_000) ... Date(timeIntervalSince1970: 15_000)
        let snapshot = batch(upserts: [], kind: .fullSnapshot, coveredDateRange: coverage)

        let merged = CalendarSyncMerger.merge(snapshot, into: [inside, outside], localCalendar: calendar, dateRange: nil)

        XCTAssertEqual(merged, [outside])
    }

    func testNewerPendingLocalVersionRecreatesAfterRemoteDelete() throws {
        let local = localEvent(
            title: "Локальная версия",
            updatedAt: Date(timeIntervalSince1970: 2_000),
            state: .pendingUpload
        )
        let deletion = DeletedRemoteEvent(
            remoteRef: RemoteEventRef(providerID: .google, remoteCalendarID: "primary", remoteEventID: "event-1"),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let batch = SyncBatch(
            upserts: [],
            deletes: [deletion],
            nextPageToken: nil,
            nextSyncToken: nil,
            kind: .incremental
        )

        let merged = CalendarSyncMerger.merge(batch, into: [local], localCalendar: calendar, dateRange: nil)

        XCTAssertEqual(merged.count, 1)
        XCTAssertNil(merged[0].externalId)
        XCTAssertNil(merged[0].externalETag)
        XCTAssertEqual(merged[0].syncState, .pendingUpload)
    }

    func testRemoteEditAfterLocalDeleteWinsDeletionConflict() throws {
        let deletedAt = Date(timeIntervalSince1970: 1_000)
        let remoteUpdatedAt = Date(timeIntervalSince1970: 2_000)
        let tombstone = PendingEventDeletion(
            remoteRef: RemoteEventRef(providerID: .google, remoteCalendarID: "primary", remoteEventID: "event-1"),
            queuedAt: deletedAt
        )
        let incoming = batch(upserts: [remoteEvent(title: "Новая серверная версия", updatedAt: remoteUpdatedAt)])

        let result = CalendarSyncMerger.resolveDeletionConflicts(in: incoming, pendingDeletions: [tombstone])

        XCTAssertEqual(result.batch.upserts.count, 1)
        XCTAssertTrue(result.pendingDeletions.isEmpty)
    }

    func testNewerLocalDeleteFiltersOlderRemoteEvent() throws {
        let remoteUpdatedAt = Date(timeIntervalSince1970: 1_000)
        let deletedAt = Date(timeIntervalSince1970: 2_000)
        let tombstone = PendingEventDeletion(
            remoteRef: RemoteEventRef(providerID: .google, remoteCalendarID: "primary", remoteEventID: "event-1"),
            queuedAt: deletedAt
        )
        let incoming = batch(upserts: [remoteEvent(title: "Старая серверная версия", updatedAt: remoteUpdatedAt)])

        let result = CalendarSyncMerger.resolveDeletionConflicts(in: incoming, pendingDeletions: [tombstone])

        XCTAssertTrue(result.batch.upserts.isEmpty)
        XCTAssertEqual(result.pendingDeletions.count, 1)
        XCTAssertEqual(result.pendingDeletions[0].id, tombstone.id)
        XCTAssertEqual(result.pendingDeletions[0].etag, "etag-1000.0")
    }

    @MainActor
    func testDeletingRemoteEventPersistsOutboxTombstone() throws {
        let event = localEvent(title: "Удалить", updatedAt: Date(), state: .clean)
        let store = InMemoryCalendarStore(
            snapshot: CalendarStoreSnapshot(calendars: [calendar], events: [event])
        )
        let viewModel = CalendarViewModel(store: store)

        viewModel.deleteEvent(event)

        XCTAssertTrue(viewModel.events.isEmpty)
        XCTAssertEqual(try store.loadPendingDeletions().map(\.remoteRef), [
            RemoteEventRef(providerID: .google, remoteCalendarID: "primary", remoteEventID: "event-1"),
        ])
    }

    private func localEvent(
        remoteID: String = "event-1",
        title: String,
        updatedAt: Date,
        state: EventSyncState
    ) -> CalendarEvent {
        CalendarEvent(
            title: title,
            startDate: Date(timeIntervalSince1970: 10_000),
            endDate: Date(timeIntervalSince1970: 13_600),
            calendarId: calendar.id,
            externalId: remoteID,
            externalProvider: .google,
            externalCalendarId: "primary",
            localUpdatedAt: updatedAt,
            remoteUpdatedAt: updatedAt,
            syncState: state
        )
    }

    private func remoteEvent(title: String, updatedAt: Date) -> ParsedRemoteEvent {
        ParsedRemoteEvent(
            remoteRef: RemoteEventRef(providerID: .google, remoteCalendarID: "primary", remoteEventID: "event-1"),
            title: title,
            start: Date(timeIntervalSince1970: 10_000),
            end: Date(timeIntervalSince1970: 13_600),
            isAllDay: false,
            notes: "",
            location: "",
            updatedAt: updatedAt,
            etag: "etag-\(updatedAt.timeIntervalSince1970)"
        )
    }

    private func batch(
        upserts: [ParsedRemoteEvent],
        kind: SyncBatchKind = .incremental,
        coveredDateRange: ClosedRange<Date>? = nil
    ) -> SyncBatch {
        SyncBatch(
            upserts: upserts,
            deletes: [],
            nextPageToken: nil,
            nextSyncToken: nil,
            kind: kind,
            coveredDateRange: coveredDateRange
        )
    }
}
