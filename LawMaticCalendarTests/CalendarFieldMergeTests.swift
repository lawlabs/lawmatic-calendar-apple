import XCTest
@testable import LawMaticCalendar

/// Трёхстороннее слияние: правки разных полей одного события, сделанные в
/// приложении и на сервере почти одновременно, сохраняются обе.
@MainActor
final class CalendarFieldMergeTests: XCTestCase {
    private let calendar = CalendarItem(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "LEGALIC · Задачи", color: .purple, accountName: "Mock",
        externalProvider: .google, externalId: "primary", isWritable: true, syncToken: "token-1"
    )
    private let remoteCalendar = RemoteCalendar(id: "primary", providerID: .google, title: "LEGALIC · Задачи", colorHex: nil, isWritable: true)
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let earlier = Date(timeIntervalSince1970: 1_790_000_000)
    private let later = Date(timeIntervalSince1970: 1_790_000_100)

    private var base: EventContent {
        EventContent(title: "Задача", notes: "", location: "Зал 5", startDate: start, endDate: start.addingTimeInterval(3600), isAllDay: false)
    }

    private func pendingEvent(_ content: EventContent, updatedAt: Date, base: EventContent?) -> CalendarEvent {
        var event = CalendarEvent(
            title: "", startDate: start, endDate: start, calendarId: calendar.id,
            externalId: "task-1", externalProvider: .google, externalCalendarId: "primary",
            externalETag: "1", localUpdatedAt: updatedAt, remoteUpdatedAt: earlier,
            syncState: .pendingUpload, remoteBase: base
        )
        event.content = content
        return event
    }

    private func remote(_ content: EventContent, updatedAt: Date, etag: String = "2") -> ParsedRemoteEvent {
        ParsedRemoteEvent(
            remoteRef: RemoteEventRef(providerID: .google, remoteCalendarID: "primary", remoteEventID: "task-1"),
            title: content.title, start: content.startDate, end: content.endDate, isAllDay: content.isAllDay,
            notes: content.notes, location: content.location, updatedAt: updatedAt, etag: etag
        )
    }

    private func merge(_ local: CalendarEvent, _ remote: ParsedRemoteEvent) -> CalendarEvent {
        let batch = SyncBatch(upserts: [remote], deletes: [], nextPageToken: nil, nextSyncToken: nil, kind: .incremental)
        return CalendarSyncMerger.merge(batch, into: [local], localCalendar: calendar, dateRange: nil)[0]
    }

    // MARK: - Слияние

    func testDifferentFieldsChangedOnBothSidesAreBothKept() {
        var local = base
        local.title = "Задача — правка календаря"
        var server = base
        server.location = "Зал 6 — правка сайта"

        // Правка в календаре позже, но локацию она не трогала.
        let merged = merge(pendingEvent(local, updatedAt: later, base: base), remote(server, updatedAt: earlier))

        XCTAssertEqual(merged.title, "Задача — правка календаря")
        XCTAssertEqual(merged.location, "Зал 6 — правка сайта")
        XCTAssertEqual(merged.syncState, .pendingUpload, "Название ещё нужно отправить")
        XCTAssertEqual(merged.remoteBase, server, "База — последняя версия сервера")
        XCTAssertEqual(merged.externalETag, "2")
    }

    func testOlderLocalEditOfAnotherFieldIsNotLost() {
        var local = base
        local.title = "Задача — правка календаря"
        var server = base
        server.location = "Зал 6"

        // Сервер новее, но название он не менял: правка календаря остаётся.
        let merged = merge(pendingEvent(local, updatedAt: earlier, base: base), remote(server, updatedAt: later))

        XCTAssertEqual(merged.title, "Задача — правка календаря")
        XCTAssertEqual(merged.location, "Зал 6")
        XCTAssertEqual(merged.syncState, .pendingUpload)
    }

    func testSameFieldChangedOnBothSidesTakesTheLaterEdit() {
        var local = base
        local.title = "Календарь"
        var server = base
        server.title = "Сайт"

        XCTAssertEqual(merge(pendingEvent(local, updatedAt: later, base: base), remote(server, updatedAt: earlier)).title, "Календарь")

        let serverWins = merge(pendingEvent(local, updatedAt: earlier, base: base), remote(server, updatedAt: later))
        XCTAssertEqual(serverWins.title, "Сайт")
        XCTAssertEqual(serverWins.syncState, .clean, "Правка проиграла целиком — отправлять нечего")
        XCTAssertNil(serverWins.remoteBase)
    }

    func testTimeIsMergedAsOneField() {
        // Календарь сдвинул конец, сайт — начало: соединить их значило бы
        // получить конец раньше начала, поэтому время берётся целиком.
        var local = base
        local.endDate = start.addingTimeInterval(2 * 3600)
        var server = base
        server.startDate = start.addingTimeInterval(3 * 3600)
        server.endDate = start.addingTimeInterval(4 * 3600)

        let merged = merge(pendingEvent(local, updatedAt: later, base: base), remote(server, updatedAt: earlier))

        XCTAssertEqual(merged.startDate, base.startDate)
        XCTAssertEqual(merged.endDate, local.endDate)
        XCTAssertLessThan(merged.startDate, merged.endDate)
    }

    func testWithoutBaseTheLaterVersionWinsWhole() {
        var local = base
        local.title = "Календарь"
        var server = base
        server.location = "Зал 6"

        let merged = merge(pendingEvent(local, updatedAt: later, base: nil), remote(server, updatedAt: earlier))

        XCTAssertEqual(merged.title, "Календарь")
        XCTAssertEqual(merged.location, "Зал 5", "Без базы — как раньше: запись целиком у более поздней правки")
    }

    // MARK: - База при правке

    func testEditingASyncedEventRemembersTheServerVersionAsBase() {
        var event = CalendarEvent(
            title: "Задача", startDate: start, endDate: start.addingTimeInterval(3600), location: "Зал 5",
            calendarId: calendar.id, externalId: "task-1", externalProvider: .google, externalCalendarId: "primary"
        )
        event.externalETag = "1"
        let viewModel = CalendarViewModel(
            store: InMemoryCalendarStore(snapshot: CalendarStoreSnapshot(calendars: [calendar], events: [event])),
            providers: MockProviderRegistry([MockCalendarProvider()]),
            saveDebounce: .seconds(60)
        )
        viewModel.sync.uploadDelay = .seconds(60)

        var edited = event
        edited.title = "Задача — правка"
        viewModel.updateEvent(edited)
        XCTAssertEqual(viewModel.events[0].remoteBase, event.content)

        var editedAgain = viewModel.events[0]
        editedAgain.location = "Зал 7"
        viewModel.updateEvent(editedAgain)
        XCTAssertEqual(viewModel.events[0].remoteBase, event.content, "Вторая правка не сдвигает базу")
    }

    // MARK: - Сквозной сценарий через синхронизацию

    func testConcurrentEditsOfDifferentFieldsBothReachTheServer() async {
        // Сценарий с dev.legalic.ru 18.10.2026: сайт поменял локацию,
        // календарь чуть позже — название той же задачи.
        let provider = MockCalendarProvider()
        provider.remoteCalendars = [remoteCalendar]
        var synced = CalendarEvent(
            title: "Задача", startDate: start, endDate: start.addingTimeInterval(3600), location: "Зал 5",
            calendarId: calendar.id, externalId: "task-1", externalProvider: .google, externalCalendarId: "primary"
        )
        synced.externalETag = "1"
        var server = base
        server.location = "Зал 6 — правка сайта"
        provider.pages["primary"] = [nil: SyncBatch(
            upserts: [remote(server, updatedAt: Date().addingTimeInterval(-5))],
            deletes: [], nextPageToken: nil, nextSyncToken: "token-2", kind: .incremental
        )]
        let viewModel = CalendarViewModel(
            store: InMemoryCalendarStore(snapshot: CalendarStoreSnapshot(calendars: [calendar], events: [synced])),
            providers: MockProviderRegistry([provider]),
            saveDebounce: .seconds(60)
        )
        viewModel.sync.uploadDelay = .seconds(60)

        var edited = synced
        edited.title = "Задача — правка календаря"
        viewModel.updateEvent(edited)
        await viewModel.syncAllProviders()

        XCTAssertEqual(provider.pushedUpserts.count, 1)
        XCTAssertEqual(provider.pushedUpserts.first?.title, "Задача — правка календаря")
        XCTAssertEqual(provider.pushedUpserts.first?.location, "Зал 6 — правка сайта")
        XCTAssertEqual(viewModel.events[0].location, "Зал 6 — правка сайта")
        XCTAssertEqual(viewModel.events[0].syncState, .clean)
        XCTAssertNil(viewModel.events[0].remoteBase)
    }

    func testEditSavedDuringPushStaysPending() async {
        let provider = MockCalendarProvider()
        provider.remoteCalendars = [remoteCalendar]
        provider.pushDelay = .milliseconds(200)
        let viewModel = CalendarViewModel(
            store: InMemoryCalendarStore(snapshot: CalendarStoreSnapshot(calendars: [calendar], events: [])),
            providers: MockProviderRegistry([provider]),
            saveDebounce: .seconds(60)
        )
        viewModel.sync.uploadDelay = .seconds(60)
        viewModel.completeEditing(
            with: CalendarEvent(title: "Новое", startDate: start, endDate: start.addingTimeInterval(3600), calendarId: calendar.id),
            isNewEvent: true
        )

        async let running: Void = viewModel.syncAllProviders()
        try? await Task.sleep(for: .milliseconds(80))
        var edited = viewModel.events[0]
        edited.title = "Новое — правка во время отправки"
        viewModel.updateEvent(edited)
        await running

        XCTAssertEqual(provider.pushedUpserts.map(\.title), ["Новое"])
        XCTAssertEqual(viewModel.events[0].title, "Новое — правка во время отправки")
        XCTAssertEqual(viewModel.events[0].syncState, .pendingUpload, "Правка во время отправки не должна считаться отправленной")
        XCTAssertNotNil(viewModel.events[0].externalId)
        XCTAssertEqual(viewModel.events[0].remoteBase?.title, "Новое")
    }
}
