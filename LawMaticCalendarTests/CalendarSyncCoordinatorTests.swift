import XCTest
@testable import LawMaticCalendar

// MARK: - Mock-провайдер

@MainActor
final class MockCalendarProvider: CalendarProvider {
    let id: ProviderID
    let displayName: String
    var status: ProviderStatus = .signedIn(accountLabel: "mock")
    var isEnabled = true

    var remoteCalendars: [RemoteCalendar] = []
    /// Страницы ответа по (calendarID, pageToken). `nil` pageToken — первая страница.
    var pages: [String: [String?: SyncBatch]] = [:]
    /// Если задано — первый запрос с этим syncToken бросает `syncTokenExpired`.
    var expiredSyncTokens: Set<String> = []
    var pushUpsertHandler: ((CalendarEvent, RemoteCalendar) throws -> PushedRemoteEvent)?
    var pushDeleteError: Error?

    private(set) var fetchRequests: [(calendarID: String, request: SyncRequest)] = []
    private(set) var pushedUpserts: [CalendarEvent] = []
    private(set) var pushedDeletes: [RemoteEventRef] = []
    private(set) var concurrentFetches = 0
    private(set) var maxConcurrentFetches = 0
    var fetchDelay: Duration = .zero

    init(id: ProviderID = .google, displayName: String = "Mock") {
        self.id = id
        self.displayName = displayName
    }

    func signIn() async throws {}
    func signOut() async {}

    func listRemoteCalendars() async throws -> [RemoteCalendar] {
        remoteCalendars
    }

    func fetchEvents(calendar: RemoteCalendar, request: SyncRequest) async throws -> SyncBatch {
        fetchRequests.append((calendar.id, request))
        concurrentFetches += 1
        maxConcurrentFetches = max(maxConcurrentFetches, concurrentFetches)
        defer { concurrentFetches -= 1 }
        if fetchDelay > .zero {
            try? await Task.sleep(for: fetchDelay)
        }
        if let token = request.syncToken, expiredSyncTokens.contains(token) {
            expiredSyncTokens.remove(token)
            throw ProviderError.syncTokenExpired
        }
        guard let page = pages[calendar.id]?[request.pageToken] else {
            return SyncBatch(upserts: [], deletes: [], nextPageToken: nil, nextSyncToken: nil, kind: request.syncToken == nil ? .fullSnapshot : .incremental)
        }
        return page
    }

    func pushUpsert(localEvent: CalendarEvent, to remoteCalendar: RemoteCalendar) async throws -> PushedRemoteEvent {
        pushedUpserts.append(localEvent)
        if let pushUpsertHandler {
            return try pushUpsertHandler(localEvent, remoteCalendar)
        }
        return PushedRemoteEvent(
            remoteRef: RemoteEventRef(
                providerID: id,
                remoteCalendarID: remoteCalendar.id,
                remoteEventID: localEvent.externalId ?? "remote-\(localEvent.id.uuidString.prefix(8))"
            ),
            etag: "etag-1",
            updatedAt: Date()
        )
    }

    func pushDelete(_ ref: RemoteEventRef, etag: String?) async throws {
        if let pushDeleteError { throw pushDeleteError }
        pushedDeletes.append(ref)
    }
}

@MainActor
final class MockProviderRegistry: CalendarProviderResolving {
    var providers: [any CalendarProvider]

    init(_ providers: [any CalendarProvider]) {
        self.providers = providers
    }

    var enabledProviders: [any CalendarProvider] {
        providers.filter(\.isEnabled)
    }

    func provider(_ id: ProviderID) -> (any CalendarProvider)? {
        providers.first { $0.id == id }
    }
}

// MARK: - Тесты

@MainActor
final class CalendarSyncCoordinatorTests: XCTestCase {
    private let remoteCalendar = RemoteCalendar(id: "primary", providerID: .google, title: "Основной", colorHex: "#4A86E8", isWritable: true)

    private func remoteEvent(_ id: String, title: String, daysFromNow: Int = 0, updatedAt: Date = Date()) -> ParsedRemoteEvent {
        let start = Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date())!
        return ParsedRemoteEvent(
            remoteRef: RemoteEventRef(providerID: .google, remoteCalendarID: "primary", remoteEventID: id),
            title: title,
            start: start,
            end: start.addingTimeInterval(3600),
            isAllDay: false,
            notes: "",
            location: "",
            updatedAt: updatedAt,
            etag: "etag-\(id)"
        )
    }

    private func makeStack(
        provider: MockCalendarProvider,
        events: [CalendarEvent] = [],
        calendars: [CalendarItem]? = nil,
        pendingDeletions: [PendingEventDeletion] = []
    ) -> (CalendarViewModel, InMemoryCalendarStore) {
        let store = InMemoryCalendarStore(
            snapshot: CalendarStoreSnapshot(
                calendars: calendars ?? CalendarSeedData.defaultCalendars(),
                events: events,
                pendingDeletions: pendingDeletions
            )
        )
        let viewModel = CalendarViewModel(
            store: store,
            providers: MockProviderRegistry([provider]),
            saveDebounce: .seconds(60)
        )
        return (viewModel, store)
    }

    func testFirstSyncCreatesLocalCalendarAndImportsAllPages() async throws {
        let provider = MockCalendarProvider()
        provider.remoteCalendars = [remoteCalendar]
        provider.pages["primary"] = [
            nil: SyncBatch(
                upserts: [remoteEvent("a", title: "A")],
                deletes: [],
                nextPageToken: "page-2",
                nextSyncToken: nil,
                kind: .fullSnapshot
            ),
            "page-2": SyncBatch(
                upserts: [remoteEvent("b", title: "B")],
                deletes: [],
                nextPageToken: nil,
                nextSyncToken: "token-1",
                kind: .fullSnapshot
            ),
        ]
        let (viewModel, store) = makeStack(provider: provider)

        await viewModel.syncAllProviders()

        XCTAssertNil(viewModel.syncError)
        XCTAssertNotNil(viewModel.lastSuccessfulSyncDate)
        let local = try XCTUnwrap(viewModel.calendars.first { $0.externalProvider == .google })
        XCTAssertEqual(local.externalId, "primary")
        XCTAssertEqual(local.syncToken, "token-1")
        XCTAssertEqual(local.accountName, "Mock")
        XCTAssertEqual(Set(viewModel.events.map(\.title)), ["A", "B"])
        XCTAssertEqual(provider.fetchRequests.map { $0.request.pageToken }, [nil, "page-2"])
        XCTAssertEqual(try store.loadEvents().count, 2)
        XCTAssertEqual(try store.loadCalendars().first { $0.externalProvider == .google }?.syncToken, "token-1")
    }

    func testExpiredSyncTokenTriggersFullResync() async throws {
        let provider = MockCalendarProvider()
        provider.remoteCalendars = [remoteCalendar]
        provider.expiredSyncTokens = ["stale"]
        provider.pages["primary"] = [
            nil: SyncBatch(
                upserts: [remoteEvent("fresh", title: "Свежее")],
                deletes: [],
                nextPageToken: nil,
                nextSyncToken: "token-2",
                kind: .fullSnapshot
            ),
        ]
        let googleCalendar = CalendarItem(
            name: "Основной", color: .blue, accountName: "Mock",
            externalProvider: .google, externalId: "primary", isWritable: true, syncToken: "stale"
        )
        let staleEvent = CalendarEvent(
            title: "Старое", startDate: Date(), endDate: Date().addingTimeInterval(3600),
            calendarId: googleCalendar.id, externalId: "old", externalProvider: .google,
            externalCalendarId: "primary", syncState: .clean
        )
        let (viewModel, _) = makeStack(provider: provider, events: [staleEvent], calendars: [googleCalendar])

        await viewModel.syncAllProviders()

        XCTAssertNil(viewModel.syncError)
        XCTAssertEqual(provider.fetchRequests.map { $0.request.syncToken }, ["stale", nil])
        XCTAssertEqual(viewModel.calendars.first?.syncToken, "token-2")
        // Полный снимок без старого события — оно удалено локально.
        XCTAssertEqual(viewModel.events.map(\.title), ["Свежее"])
    }

    func testPendingLocalChangesArePushedAfterPull() async throws {
        let provider = MockCalendarProvider()
        provider.remoteCalendars = [remoteCalendar]
        let googleCalendar = CalendarItem(
            name: "Основной", color: .blue, accountName: "Mock",
            externalProvider: .google, externalId: "primary", isWritable: true, syncToken: "token-1"
        )
        let (viewModel, store) = makeStack(provider: provider, calendars: [googleCalendar])

        var created = CalendarEvent(
            title: "Новое", startDate: Date(), endDate: Date().addingTimeInterval(3600),
            calendarId: googleCalendar.id
        )
        viewModel.completeEditing(with: created, isNewEvent: true)
        created = try XCTUnwrap(viewModel.events.first)
        XCTAssertEqual(created.syncState, .pendingUpload)

        await viewModel.syncAllProviders()

        XCTAssertNil(viewModel.syncError)
        XCTAssertEqual(provider.pushedUpserts.map(\.title), ["Новое"])
        let synced = try XCTUnwrap(viewModel.events.first)
        XCTAssertEqual(synced.syncState, .clean)
        XCTAssertNotNil(synced.externalId)
        XCTAssertEqual(synced.externalETag, "etag-1")
        XCTAssertEqual(try store.loadEvents().first?.syncState, .clean)
    }

    func testQueuedDeletionIsPushedAndDequeued() async throws {
        let provider = MockCalendarProvider()
        provider.remoteCalendars = [remoteCalendar]
        let googleCalendar = CalendarItem(
            name: "Основной", color: .blue, accountName: "Mock",
            externalProvider: .google, externalId: "primary", isWritable: true, syncToken: "token-1"
        )
        let event = CalendarEvent(
            title: "Удалить", startDate: Date(), endDate: Date().addingTimeInterval(3600),
            calendarId: googleCalendar.id, externalId: "r-1", externalProvider: .google,
            externalCalendarId: "primary", externalETag: "e1", syncState: .clean
        )
        let (viewModel, store) = makeStack(provider: provider, events: [event], calendars: [googleCalendar])

        viewModel.deleteEvent(event)
        XCTAssertEqual(viewModel.pendingDeletions.count, 1)

        await viewModel.syncAllProviders()

        XCTAssertNil(viewModel.syncError)
        XCTAssertEqual(provider.pushedDeletes.map(\.remoteEventID), ["r-1"])
        XCTAssertTrue(viewModel.pendingDeletions.isEmpty)
        XCTAssertTrue(try store.loadPendingDeletions().isEmpty)
    }

    func testFailedPushKeepsPendingStateForRetry() async throws {
        let provider = MockCalendarProvider()
        provider.remoteCalendars = [remoteCalendar]
        provider.pushUpsertHandler = { _, _ in throw ProviderError.httpStatus(503, nil) }
        let googleCalendar = CalendarItem(
            name: "Основной", color: .blue, accountName: "Mock",
            externalProvider: .google, externalId: "primary", isWritable: true, syncToken: "token-1"
        )
        let (viewModel, _) = makeStack(provider: provider, calendars: [googleCalendar])
        viewModel.completeEditing(
            with: CalendarEvent(title: "Новое", startDate: Date(), endDate: Date().addingTimeInterval(3600), calendarId: googleCalendar.id),
            isNewEvent: true
        )

        await viewModel.syncAllProviders()

        XCTAssertNotNil(viewModel.syncError)
        XCTAssertEqual(viewModel.events.first?.syncState, .pendingUpload)
        XCTAssertNil(viewModel.lastSuccessfulSyncDate)
    }

    func testConcurrentSyncOfSameProviderIsIgnored() async throws {
        let provider = MockCalendarProvider()
        provider.remoteCalendars = [remoteCalendar]
        provider.fetchDelay = .milliseconds(50)
        let (viewModel, _) = makeStack(provider: provider)

        async let first: Void = viewModel.syncAllProviders()
        async let second: Void = viewModel.syncAllProviders()
        _ = await (first, second)

        XCTAssertEqual(provider.fetchRequests.count, 1, "Второй запуск должен быть отброшен, пока идёт первый")
        XCTAssertEqual(provider.maxConcurrentFetches, 1)
    }

    func testStaleSyncWindowForcesFullResync() async throws {
        let provider = MockCalendarProvider()
        provider.remoteCalendars = [remoteCalendar]
        let windowEnd = Calendar.current.date(byAdding: .month, value: 2, to: Date())!
        let newWindow = Date() ... Calendar.current.date(byAdding: .year, value: 3, to: Date())!
        provider.pages["primary"] = [
            nil: SyncBatch(
                upserts: [], deletes: [], nextPageToken: nil, nextSyncToken: "token-3",
                kind: .fullSnapshot, coveredDateRange: newWindow
            ),
        ]
        let googleCalendar = CalendarItem(
            name: "Основной", color: .blue, accountName: "Mock",
            externalProvider: .google, externalId: "primary", isWritable: true,
            syncToken: "token-old", syncWindowEnd: windowEnd
        )
        let (viewModel, _) = makeStack(provider: provider, calendars: [googleCalendar])

        await viewModel.syncAllProviders()

        XCTAssertEqual(provider.fetchRequests.map { $0.request.syncToken }, [nil])
        XCTAssertEqual(viewModel.calendars.first?.syncToken, "token-3")
        XCTAssertEqual(viewModel.calendars.first?.syncWindowEnd, newWindow.upperBound)
    }

    func testVanishedRemoteCalendarIsRemovedWithItsEvents() async throws {
        let provider = MockCalendarProvider()
        provider.remoteCalendars = [remoteCalendar]
        let kept = CalendarItem(
            name: "Основной", color: .blue, accountName: "Mock",
            externalProvider: .google, externalId: "primary", isWritable: true
        )
        let vanished = CalendarItem(
            name: "Старый", color: .red, accountName: "Mock",
            externalProvider: .google, externalId: "gone", isWritable: true
        )
        let orphan = CalendarEvent(
            title: "Сирота", startDate: Date(), endDate: Date().addingTimeInterval(3600),
            calendarId: vanished.id, externalId: "x", externalProvider: .google, externalCalendarId: "gone"
        )
        let tombstone = PendingEventDeletion(
            remoteRef: RemoteEventRef(providerID: .google, remoteCalendarID: "gone", remoteEventID: "y")
        )
        let (viewModel, store) = makeStack(
            provider: provider, events: [orphan], calendars: [kept, vanished], pendingDeletions: [tombstone]
        )

        await viewModel.syncAllProviders()

        XCTAssertEqual(viewModel.calendars.map(\.externalId), ["primary"])
        XCTAssertTrue(viewModel.events.isEmpty)
        XCTAssertTrue(viewModel.pendingDeletions.isEmpty)
        XCTAssertEqual(try store.loadCalendars().count, 1)
        XCTAssertTrue(provider.pushedDeletes.isEmpty, "Tombstone исчезнувшего календаря не должен уходить на сервер")
    }

    func testDisabledProviderProducesFriendlyError() async throws {
        let provider = MockCalendarProvider()
        provider.isEnabled = false
        let (viewModel, _) = makeStack(provider: provider)

        await viewModel.syncAllProviders()

        XCTAssertEqual(viewModel.syncError?.message, "Включите хотя бы один аккаунт в настройках.")
        XCTAssertTrue(provider.fetchRequests.isEmpty)
    }
}
