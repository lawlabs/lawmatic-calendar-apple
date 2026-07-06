import XCTest
@testable import LawMaticCalendar

@MainActor
final class CalendarViewModelTests: XCTestCase {
    func testNewEventIsSavedToStore() throws {
        let store = InMemoryCalendarStore(
            snapshot: CalendarStoreSnapshot(
                calendars: CalendarSeedData.defaultCalendars(),
                events: []
            )
        )
        let viewModel = CalendarViewModel(store: store)

        let calendarID = try XCTUnwrap(viewModel.calendars.first?.id)
        let startDate = Date()
        let endDate = startDate.addingTimeInterval(3600)

        let event = CalendarEvent(
            title: "Smoke event",
            startDate: startDate,
            endDate: endDate,
            calendarId: calendarID
        )

        viewModel.completeEditing(with: event, isNewEvent: true)

        XCTAssertEqual(viewModel.events.count, 1)
        XCTAssertEqual(viewModel.selectedEventId, event.id)
        XCTAssertEqual(try store.loadEvents(), [event])
    }

    func testToggleCalendarVisibilityPersistsCalendarState() throws {
        let store = InMemoryCalendarStore(
            snapshot: CalendarStoreSnapshot(
                calendars: CalendarSeedData.defaultCalendars(),
                events: []
            )
        )
        let viewModel = CalendarViewModel(store: store)
        let calendar = try XCTUnwrap(viewModel.calendars.first)

        viewModel.toggleCalendarVisibility(calendar)

        let persistedCalendar = try XCTUnwrap(store.loadCalendars().first(where: { $0.id == calendar.id }))
        XCTAssertFalse(persistedCalendar.isVisible)
    }

    func testCreateInspectorStartsInEditingMode() throws {
        let store = InMemoryCalendarStore(
            snapshot: CalendarStoreSnapshot(
                calendars: CalendarSeedData.defaultCalendars(),
                events: []
            )
        )
        let viewModel = CalendarViewModel(store: store)

        viewModel.createNewEvent(referenceDate: Date())

        XCTAssertTrue(viewModel.isInspectorPresented)
        XCTAssertTrue(viewModel.isEditingEvent)
        XCTAssertNotNil(viewModel.selectedEvent)
        XCTAssertTrue(try store.loadEvents().isEmpty)
    }

    func testDiscardNewDraftRemovesUnsavedEvent() throws {
        let store = InMemoryCalendarStore(
            snapshot: CalendarStoreSnapshot(
                calendars: CalendarSeedData.defaultCalendars(),
                events: []
            )
        )
        let viewModel = CalendarViewModel(store: store)

        viewModel.createNewEvent(referenceDate: Date())
        let draftID = try XCTUnwrap(viewModel.selectedEvent?.id)

        viewModel.discardEditing()

        XCTAssertFalse(viewModel.isInspectorPresented)
        XCTAssertFalse(viewModel.events.contains(where: { $0.id == draftID }))
        XCTAssertTrue(try store.loadEvents().isEmpty)
    }

    func testUpdatePendingNewEventUpdatesDraftWithoutSaving() throws {
        let store = InMemoryCalendarStore(
            snapshot: CalendarStoreSnapshot(
                calendars: CalendarSeedData.defaultCalendars(),
                events: []
            )
        )
        let viewModel = CalendarViewModel(store: store)
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
        let end = calendar.date(bySettingHour: 11, minute: 30, second: 0, of: Date())!

        viewModel.updatePendingNewEvent(startDate: start, endDate: end)

        let draftEvent = try XCTUnwrap(viewModel.selectedEvent)
        XCTAssertEqual(draftEvent.startDate, start)
        XCTAssertEqual(draftEvent.endDate, end)
        XCTAssertTrue(viewModel.isEditingEvent)
        XCTAssertTrue(try store.loadEvents().isEmpty)
    }

    func testSelectingExistingEventDiscardsUntitledDraft() throws {
        let calendars = CalendarSeedData.defaultCalendars()
        let existingEvent = CalendarEvent(
            title: "Persisted",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            calendarId: calendars[0].id
        )
        let store = InMemoryCalendarStore(
            snapshot: CalendarStoreSnapshot(
                calendars: calendars,
                events: [existingEvent]
            )
        )
        let viewModel = CalendarViewModel(store: store)

        viewModel.createNewEvent(referenceDate: Date())
        let draftID = try XCTUnwrap(viewModel.selectedEvent?.id)

        viewModel.selectEvent(existingEvent)

        XCTAssertFalse(viewModel.events.contains(where: { $0.id == draftID }))
        XCTAssertEqual(viewModel.selectedEventId, existingEvent.id)
    }

    func testApplyInspectorChangesPersistsDraftWhenTitleAppears() throws {
        let store = InMemoryCalendarStore(
            snapshot: CalendarStoreSnapshot(
                calendars: CalendarSeedData.defaultCalendars(),
                events: []
            )
        )
        let viewModel = CalendarViewModel(store: store)

        viewModel.createNewEvent(referenceDate: Date())
        let draft = try XCTUnwrap(viewModel.selectedEvent)
        let updatedDraft = CalendarEvent(
            id: draft.id,
            title: "Новый клиент",
            startDate: draft.startDate,
            endDate: draft.endDate,
            isAllDay: draft.isAllDay,
            notes: draft.notes,
            location: draft.location,
            calendarId: draft.calendarId
        )

        viewModel.applyInspectorChanges(updatedDraft)

        XCTAssertEqual(try store.loadEvents(), [updatedDraft])
        XCTAssertEqual(viewModel.selectedEventId, updatedDraft.id)
        XCTAssertFalse(viewModel.isEditingEvent)
    }

    func testClearSelectionClosesInspectorForExistingEvent() throws {
        let calendars = CalendarSeedData.defaultCalendars()
        let existingEvent = CalendarEvent(
            title: "Встреча",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            calendarId: calendars[0].id
        )
        let store = InMemoryCalendarStore(
            snapshot: CalendarStoreSnapshot(
                calendars: calendars,
                events: [existingEvent]
            )
        )
        let viewModel = CalendarViewModel(store: store)

        viewModel.selectEvent(existingEvent)
        viewModel.clearSelection()

        XCTAssertNil(viewModel.selectedEventId)
        XCTAssertFalse(viewModel.isInspectorPresented)
        XCTAssertEqual(viewModel.events, [existingEvent])
    }

    func testClearSelectionRemovesUntitledDraft() throws {
        let store = InMemoryCalendarStore(
            snapshot: CalendarStoreSnapshot(
                calendars: CalendarSeedData.defaultCalendars(),
                events: []
            )
        )
        let viewModel = CalendarViewModel(store: store)

        viewModel.createNewEvent(referenceDate: Date())
        let draftID = try XCTUnwrap(viewModel.selectedEvent?.id)

        viewModel.clearSelection()

        XCTAssertNil(viewModel.selectedEventId)
        XCTAssertFalse(viewModel.isInspectorPresented)
        XCTAssertFalse(viewModel.events.contains(where: { $0.id == draftID }))
        XCTAssertTrue(try store.loadEvents().isEmpty)
    }

    func testQuickCreateDurationStopsAtEndOfDay() {
        let viewModel = CalendarViewModel(
            store: InMemoryCalendarStore(
                snapshot: CalendarStoreSnapshot(
                    calendars: CalendarSeedData.defaultCalendars(),
                    events: []
                )
            )
        )
        let calendar = Calendar.current
        let lateStart = calendar.date(bySettingHour: 23, minute: 45, second: 0, of: Date())!

        let duration = viewModel.defaultDurationForQuickCreate(at: lateStart)

        XCTAssertEqual(duration, 15 * 60)
    }
}
