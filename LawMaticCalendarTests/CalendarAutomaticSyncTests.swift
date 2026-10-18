import XCTest
@testable import LawMaticCalendar

/// Синхронизация без кнопки: правки уходят сами, обновление идёт по
/// устареванию аккаунта, ошибки снимаются успешным прогоном.
@MainActor
final class CalendarAutomaticSyncTests: XCTestCase {
    private let remoteCalendar = RemoteCalendar(id: "primary", providerID: .google, title: "Основной", colorHex: "#4A86E8", isWritable: true)
    private let googleCalendar = CalendarItem(
        name: "Основной", color: .blue, accountName: "Mock",
        externalProvider: .google, externalId: "primary", isWritable: true, syncToken: "token-1"
    )

    private func makeViewModel(_ provider: MockCalendarProvider) -> CalendarViewModel {
        provider.remoteCalendars = [remoteCalendar]
        let store = InMemoryCalendarStore(
            snapshot: CalendarStoreSnapshot(calendars: [googleCalendar], events: [])
        )
        let viewModel = CalendarViewModel(store: store, providers: MockProviderRegistry([provider]))
        viewModel.sync.uploadDelay = .milliseconds(10)
        return viewModel
    }

    private func newGoogleEvent(_ title: String) -> CalendarEvent {
        CalendarEvent(title: title, startDate: Date(), endDate: Date().addingTimeInterval(3600), calendarId: googleCalendar.id)
    }

    private func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testSavedEditReachesTheServerWithoutManualSync() async {
        let provider = MockCalendarProvider()
        let viewModel = makeViewModel(provider)

        viewModel.completeEditing(with: newGoogleEvent("Новое"), isNewEvent: true)
        await waitUntil { viewModel.events.first?.syncState == .clean }

        XCTAssertEqual(provider.pushedUpserts.map(\.title), ["Новое"])
        XCTAssertEqual(viewModel.events.first?.syncState, .clean)
        XCTAssertNotNil(provider.lastSyncDate)
    }

    func testDraftInTheInspectorIsNotUploaded() async throws {
        let provider = MockCalendarProvider()
        let viewModel = makeViewModel(provider)
        viewModel.createNewEvent(at: Date())
        guard case .create(let draftID) = viewModel.inspectorState else {
            return XCTFail("Ожидался черновик в инспекторе")
        }
        var draft = try XCTUnwrap(viewModel.events.first { $0.id == draftID })
        draft.calendarId = googleCalendar.id
        viewModel.applyInspectorChanges(draft)
        XCTAssertEqual(viewModel.events.first { $0.id == draftID }?.syncState, .pendingUpload)

        await viewModel.syncAllProviders()

        XCTAssertTrue(provider.pushedUpserts.isEmpty, "Несохранённый черновик ушёл на сервер")
    }

    func testEditSavedDuringSyncGetsAnotherPass() async {
        let provider = MockCalendarProvider()
        provider.fetchDelay = .milliseconds(200)
        let viewModel = makeViewModel(provider)
        viewModel.sync.uploadDelay = .zero

        async let running: Void = viewModel.syncAllProviders()
        try? await Task.sleep(for: .milliseconds(50))
        viewModel.completeEditing(with: newGoogleEvent("Во время синхронизации"), isNewEvent: true)
        await running
        await waitUntil { provider.fetchRequests.count == 2 && !viewModel.isSyncing }

        XCTAssertEqual(provider.pushedUpserts.map(\.title), ["Во время синхронизации"])
        XCTAssertEqual(provider.fetchRequests.count, 2, "Правка во время прогона должна получить ещё один проход")
        XCTAssertEqual(viewModel.events.first?.syncState, .clean)
    }

    func testAutomaticRefreshSkipsRecentlySyncedAccounts() async {
        let provider = MockCalendarProvider()
        let viewModel = makeViewModel(provider)

        provider.lastSyncDate = Date()
        await viewModel.sync.refreshStaleProviders(olderThan: 60)
        XCTAssertTrue(provider.fetchRequests.isEmpty)

        provider.lastSyncDate = Date().addingTimeInterval(-10 * 60)
        await viewModel.sync.refreshStaleProviders(olderThan: 60)
        XCTAssertFalse(provider.fetchRequests.isEmpty)
    }

    func testSuccessfulRunClearsTheAccountError() async {
        let provider = MockCalendarProvider()
        provider.pushUpsertHandler = { _, _ in throw URLError(.notConnectedToInternet) }
        let viewModel = makeViewModel(provider)
        viewModel.sync.uploadDelay = .seconds(60)
        viewModel.completeEditing(with: newGoogleEvent("Офлайн"), isNewEvent: true)

        await viewModel.syncAllProviders()
        XCTAssertNotNil(viewModel.syncError)
        XCTAssertNil(viewModel.lastSuccessfulSyncDate)

        provider.pushUpsertHandler = nil
        await viewModel.syncAllProviders()
        XCTAssertNil(viewModel.syncError)
        XCTAssertNotNil(viewModel.lastSuccessfulSyncDate)
        XCTAssertEqual(viewModel.events.first?.syncState, .clean)
    }
}

/// Аккаунт выключен или без доступа: его календари только для чтения, а
/// неотправленные правки видны в предупреждении и уходят после подключения.
@MainActor
final class CalendarAccountAvailabilityTests: XCTestCase {
    private let remoteCalendar = RemoteCalendar(id: "primary", providerID: .google, title: "Основной", colorHex: "#4A86E8", isWritable: true)
    private let googleCalendar = CalendarItem(
        name: "Основной", color: .blue, accountName: "Mock",
        externalProvider: .google, externalId: "primary", isWritable: true, syncToken: "token-1"
    )
    private let localCalendar = CalendarItem(name: "Личный", color: .green, accountName: "Локально")

    private func makeViewModel(_ provider: MockCalendarProvider, events: [CalendarEvent] = []) -> CalendarViewModel {
        provider.remoteCalendars = [remoteCalendar]
        let store = InMemoryCalendarStore(
            snapshot: CalendarStoreSnapshot(calendars: [googleCalendar, localCalendar], events: events)
        )
        let viewModel = CalendarViewModel(store: store, providers: MockProviderRegistry([provider]))
        viewModel.sync.uploadDelay = .milliseconds(10)
        return viewModel
    }

    private func editedGoogleEvent() -> CalendarEvent {
        var event = CalendarEvent(title: "Повестки", startDate: Date(), endDate: Date().addingTimeInterval(3600), calendarId: googleCalendar.id)
        event.externalProvider = .google
        event.externalCalendarId = "primary"
        event.externalId = "remote-1"
        event.syncState = .pendingUpload
        return event
    }

    private func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testDisabledAccountMakesItsCalendarsReadOnly() {
        let provider = MockCalendarProvider()
        provider.isEnabled = false
        let event = editedGoogleEvent()
        let viewModel = makeViewModel(provider, events: [event])

        XCTAssertFalse(viewModel.canEdit(event))
        XCTAssertFalse(viewModel.canWrite(to: googleCalendar))
        XCTAssertTrue(viewModel.canWrite(to: localCalendar))
        XCTAssertEqual(viewModel.defaultCalendarId, localCalendar.id)
        XCTAssertEqual(viewModel.writableCalendarIDs, [localCalendar.id])
    }

    func testUnsentChangesAreAnnouncedWhileTheAccountIsOff() {
        let provider = MockCalendarProvider()
        provider.isEnabled = false
        let viewModel = makeViewModel(provider, events: [editedGoogleEvent()])

        XCTAssertEqual(
            viewModel.unsentChangesNotice,
            "Google Calendar не подключён: 1 правка не отправлена. Подключите аккаунт в настройках — изменения уйдут сразу."
        )
    }

    func testNoNoticeWhileTheAccountIsOn() {
        let provider = MockCalendarProvider()
        let viewModel = makeViewModel(provider, events: [editedGoogleEvent()])

        XCTAssertNil(viewModel.unsentChangesNotice)
        XCTAssertTrue(viewModel.canEdit(viewModel.events[0]))
    }

    func testReconnectingTheAccountSendsPendingChanges() async {
        let provider = MockCalendarProvider()
        provider.isEnabled = false
        let viewModel = makeViewModel(provider, events: [editedGoogleEvent()])
        XCTAssertNotNil(viewModel.unsentChangesNotice)

        provider.isEnabled = true
        await waitUntil { viewModel.events.first?.syncState == .clean }

        XCTAssertEqual(provider.pushedUpserts.map(\.title), ["Повестки"])
        XCTAssertNil(viewModel.unsentChangesNotice)
        XCTAssertTrue(viewModel.canEdit(viewModel.events[0]))
    }

    func testUnsentChangesPhraseAgreesWithTheNumber() {
        XCTAssertEqual(CalendarViewModel.unsentChangesPhrase(1), "1 правка не отправлена")
        XCTAssertEqual(CalendarViewModel.unsentChangesPhrase(3), "3 правки не отправлены")
        XCTAssertEqual(CalendarViewModel.unsentChangesPhrase(5), "5 правок не отправлено")
        XCTAssertEqual(CalendarViewModel.unsentChangesPhrase(11), "11 правок не отправлено")
        XCTAssertEqual(CalendarViewModel.unsentChangesPhrase(21), "21 правка не отправлена")
        XCTAssertEqual(CalendarViewModel.unsentChangesPhrase(22), "22 правки не отправлены")
        XCTAssertEqual(CalendarViewModel.unsentChangesPhrase(112), "112 правок не отправлено")
    }
}
