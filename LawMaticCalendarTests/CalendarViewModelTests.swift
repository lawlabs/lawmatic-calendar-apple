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

// MARK: - Индекс событий по дням

@MainActor
final class CalendarViewModelEventIndexTests: XCTestCase {
    private let calendars = CalendarSeedData.defaultCalendars()

    private func makeViewModel(events: [CalendarEvent] = []) -> (CalendarViewModel, InMemoryCalendarStore) {
        let store = InMemoryCalendarStore(
            snapshot: CalendarStoreSnapshot(
                calendars: calendars,
                events: events
            )
        )
        return (CalendarViewModel(store: store, saveDebounce: .seconds(60)), store)
    }

    func testMultiDayEventAppearsOnEveryCoveredDayRegardlessOfQueryTime() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let start = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: yesterday)!
        let end = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
        let event = CalendarEvent(title: "Ночной", startDate: start, endDate: end, calendarId: calendars[0].id)
        let (viewModel, _) = makeViewModel(events: [event])

        // Запрос в середине дня, позже конца события — раньше событие терялось.
        let midday = calendar.date(bySettingHour: 14, minute: 37, second: 0, of: today)!

        XCTAssertEqual(viewModel.events(for: midday).map(\.id), [event.id])
        XCTAssertEqual(viewModel.events(for: yesterday).map(\.id), [event.id])
        XCTAssertTrue(viewModel.hasEvents(on: midday))
    }

    func testEventEndingExactlyAtMidnightDoesNotLeakIntoNextDay() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let start = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: today)!
        let event = CalendarEvent(title: "До полуночи", startDate: start, endDate: tomorrow, calendarId: calendars[0].id)
        let (viewModel, _) = makeViewModel(events: [event])

        XCTAssertEqual(viewModel.events(for: today).map(\.id), [event.id])
        XCTAssertTrue(viewModel.events(for: tomorrow).isEmpty)
        XCTAssertFalse(viewModel.hasEvents(on: tomorrow))
    }

    func testHiddenCalendarEventsAreExcludedFromDayQueries() throws {
        let event = CalendarEvent(
            title: "Скрытый",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            calendarId: calendars[0].id
        )
        let (viewModel, _) = makeViewModel(events: [event])

        viewModel.toggleCalendarVisibility(calendars[0])

        XCTAssertTrue(viewModel.events(for: Date()).isEmpty)
        XCTAssertFalse(viewModel.hasEvents(on: Date()))
        XCTAssertTrue(viewModel.upcomingEvents(from: Date().addingTimeInterval(-60)).isEmpty)
    }

    func testUpcomingEventsAreSortedAndLimited() throws {
        let now = Date()
        var events: [CalendarEvent] = []
        for offset in 1...8 {
            let hoursAhead = 9 - offset
            let start = now.addingTimeInterval(Double(hoursAhead) * 3600)
            events.append(
                CalendarEvent(
                    title: "Событие \(offset)",
                    startDate: start,
                    endDate: start.addingTimeInterval(1800),
                    calendarId: calendars[0].id
                )
            )
        }
        let (viewModel, _) = makeViewModel(events: events)

        let upcoming = viewModel.upcomingEvents(from: now, limit: 3)

        XCTAssertEqual(upcoming.map(\.title), ["Событие 8", "Событие 7", "Событие 6"])
    }
}

// MARK: - Отложенное сохранение

@MainActor
final class CalendarViewModelPersistenceTests: XCTestCase {
    private let calendars = CalendarSeedData.defaultCalendars()

    private func makeViewModel(events: [CalendarEvent]) -> (CalendarViewModel, InMemoryCalendarStore) {
        let store = InMemoryCalendarStore(
            snapshot: CalendarStoreSnapshot(
                calendars: calendars,
                events: events
            )
        )
        return (CalendarViewModel(store: store, saveDebounce: .seconds(60)), store)
    }

    private func makeEvent() -> CalendarEvent {
        CalendarEvent(
            title: "Встреча",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            calendarId: calendars[0].id
        )
    }

    func testInspectorEditsOfExistingEventAreDebounced() throws {
        let event = makeEvent()
        let (viewModel, store) = makeViewModel(events: [event])
        viewModel.selectEvent(event)

        var edited = event
        edited.title = "Встреча с клиентом"
        viewModel.applyInspectorChanges(edited)

        XCTAssertEqual(viewModel.selectedEvent?.title, "Встреча с клиентом")
        XCTAssertTrue(viewModel.hasPendingSaves)
        XCTAssertEqual(try store.loadEvents().map(\.title), ["Встреча"], "Покомпонентная правка не должна писать на диск сразу")

        viewModel.flushPendingSaves()

        XCTAssertFalse(viewModel.hasPendingSaves)
        XCTAssertEqual(try store.loadEvents().map(\.title), ["Встреча с клиентом"])
    }

    func testClosingInspectorFlushesPendingSaves() throws {
        let event = makeEvent()
        let (viewModel, store) = makeViewModel(events: [event])
        viewModel.selectEvent(event)

        var edited = event
        edited.location = "Офис"
        viewModel.applyInspectorChanges(edited)
        viewModel.closeInspector()

        XCTAssertFalse(viewModel.hasPendingSaves)
        XCTAssertEqual(try store.loadEvents().first?.location, "Офис")
    }

    func testSelectingAnotherEventFlushesPendingSaves() throws {
        let first = makeEvent()
        var second = makeEvent()
        second.title = "Вторая"
        let (viewModel, store) = makeViewModel(events: [first, second])
        viewModel.selectEvent(first)

        var edited = first
        edited.notes = "Заметка"
        viewModel.applyInspectorChanges(edited)
        viewModel.selectEvent(second)

        XCTAssertFalse(viewModel.hasPendingSaves)
        XCTAssertEqual(try store.loadEvents().first(where: { $0.id == first.id })?.notes, "Заметка")
    }

    func testDragUpdateIsSavedImmediately() throws {
        let event = makeEvent()
        let (viewModel, store) = makeViewModel(events: [event])

        var moved = event
        moved.startDate = event.startDate.addingTimeInterval(900)
        moved.endDate = event.endDate.addingTimeInterval(900)
        viewModel.updateEvent(moved)

        XCTAssertFalse(viewModel.hasPendingSaves)
        XCTAssertEqual(try store.loadEvents().first?.startDate, moved.startDate)
    }
}

// MARK: - Undo

@MainActor
final class CalendarViewModelUndoTests: XCTestCase {
    private let calendars = CalendarSeedData.defaultCalendars()

    private func makeViewModel(events: [CalendarEvent]) -> (CalendarViewModel, InMemoryCalendarStore, UndoManager) {
        let store = InMemoryCalendarStore(
            snapshot: CalendarStoreSnapshot(calendars: calendars, events: events)
        )
        let viewModel = CalendarViewModel(store: store, saveDebounce: .seconds(60))
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        return (viewModel, store, undoManager)
    }

    private func makeEvent(title: String = "Встреча") -> CalendarEvent {
        CalendarEvent(
            title: title,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            calendarId: calendars[0].id
        )
    }

    func testDeleteCanBeUndoneAndRedone() throws {
        let event = makeEvent()
        let (viewModel, store, undoManager) = makeViewModel(events: [event])

        viewModel.deleteEvent(event)
        XCTAssertTrue(viewModel.events.isEmpty)
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()
        XCTAssertEqual(viewModel.events.map(\.id), [event.id])
        XCTAssertEqual(try store.loadEvents().map(\.id), [event.id])
        XCTAssertEqual(viewModel.selectedEventId, event.id)

        undoManager.redo()
        XCTAssertTrue(viewModel.events.isEmpty)
    }

    func testDragUpdateCanBeUndone() throws {
        let event = makeEvent()
        let (viewModel, store, undoManager) = makeViewModel(events: [event])

        var moved = event
        moved.startDate = event.startDate.addingTimeInterval(1800)
        moved.endDate = event.endDate.addingTimeInterval(1800)
        viewModel.updateEvent(moved)
        XCTAssertEqual(viewModel.events.first?.startDate, moved.startDate)

        undoManager.undo()

        XCTAssertEqual(viewModel.events.first?.startDate, event.startDate)
        XCTAssertEqual(try store.loadEvents().first?.startDate, event.startDate)
    }

    func testDebouncedInspectorEditsDoNotSpamUndoStack() throws {
        let event = makeEvent()
        let (viewModel, _, undoManager) = makeViewModel(events: [event])
        viewModel.selectEvent(event)

        for suffix in ["В", "Вс", "Вст"] {
            var edited = event
            edited.title = suffix
            viewModel.applyInspectorChanges(edited)
        }

        XCTAssertFalse(undoManager.canUndo)
    }

    func testUndoingDeleteOfRemoteEventCancelsQueuedTombstone() throws {
        var calendars = self.calendars
        calendars[0].externalProvider = .google
        calendars[0].externalId = "primary"
        var event = makeEvent()
        event.externalProvider = .google
        event.externalCalendarId = "primary"
        event.externalId = "remote-1"
        let store = InMemoryCalendarStore(
            snapshot: CalendarStoreSnapshot(calendars: calendars, events: [event])
        )
        let viewModel = CalendarViewModel(store: store, saveDebounce: .seconds(60))
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager

        viewModel.deleteEvent(event)
        XCTAssertEqual(viewModel.pendingDeletions.count, 1)

        undoManager.undo()

        XCTAssertTrue(viewModel.pendingDeletions.isEmpty)
        XCTAssertEqual(viewModel.events.first?.externalId, "remote-1")
        XCTAssertEqual(viewModel.events.first?.syncState, .clean)
    }
}

// MARK: - Инкрементальный индекс

@MainActor
final class EventRepositoryIndexTests: XCTestCase {
    private let calendars = CalendarSeedData.defaultCalendars()

    private func makeRepository(events: [CalendarEvent]) -> EventRepository {
        EventRepository(
            store: InMemoryCalendarStore(snapshot: CalendarStoreSnapshot(calendars: calendars, events: events)),
            saveDebounce: .seconds(60)
        )
    }

    private func event(_ title: String, day: Int, hour: Int, durationHours: Int = 1) -> CalendarEvent {
        let calendar = Calendar.current
        let base = calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
        return CalendarEvent(
            title: title,
            startDate: base,
            endDate: base.addingTimeInterval(TimeInterval(durationHours * 3600)),
            calendarId: calendars[0].id
        )
    }

    private func day(_ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: day))!
    }

    func testInPlaceEditMovesEventBetweenDaysAndKeepsOrder() {
        let repository = makeRepository(events: [event("A", day: 10, hour: 9), event("B", day: 10, hour: 12)])

        var moved = repository.events[1]
        moved.startDate = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 8))!
        moved.endDate = moved.startDate.addingTimeInterval(3600)
        repository.events[1] = moved

        XCTAssertEqual(repository.events(for: day(10)).map(\.title), ["A"])
        XCTAssertEqual(repository.events(for: day(11)).map(\.title), ["B"])

        var earlier = repository.events[0]
        earlier.startDate = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 7))!
        earlier.endDate = earlier.startDate.addingTimeInterval(3600)
        repository.events[0] = earlier

        XCTAssertTrue(repository.events(for: day(10)).isEmpty)
        XCTAssertEqual(repository.events(for: day(11)).map(\.title), ["A", "B"], "Вставка сохраняет сортировку по началу")
    }

    func testAppendAndRemoveUpdateIndexIncrementally() {
        let repository = makeRepository(events: [event("A", day: 10, hour: 9)])

        repository.events.append(event("C", day: 10, hour: 8, durationHours: 30))
        XCTAssertEqual(repository.events(for: day(10)).map(\.title), ["C", "A"])
        XCTAssertEqual(repository.events(for: day(11)).map(\.title), ["C"], "Многодневное событие попадает во все дни")

        repository.events.removeAll { $0.title == "C" }
        XCTAssertEqual(repository.events(for: day(10)).map(\.title), ["A"])
        XCTAssertFalse(repository.hasEvents(on: day(11)))
    }

    func testBulkReplacementRebuildsIndex() {
        let repository = makeRepository(events: [event("A", day: 10, hour: 9)])

        repository.events = (1...20).map { event("E\($0)", day: 12, hour: $0 % 12) }

        XCTAssertTrue(repository.events(for: day(10)).isEmpty)
        XCTAssertEqual(repository.events(for: day(12)).count, 20)
        let starts = repository.events(for: day(12)).map(\.startDate)
        XCTAssertEqual(starts, starts.sorted())
    }
}
