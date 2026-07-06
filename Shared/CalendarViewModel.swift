import Combine
import SwiftUI

private let legalicRangeLogFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.timeZone = TimeZone.current
    return formatter
}()

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published var events: [CalendarEvent] = []
    @Published var calendars: [CalendarItem] = []
    @Published var selectedDate: Date = Date()
    @Published var viewMode: ViewMode = .day
    @Published var inspectorState: EventInspectorState?
    @Published var storageError: IdentifiableMessage?
    @Published var isLegalicSyncing = false
    @Published var legalicSyncError: IdentifiableMessage?

    private let store: CalendarStore
    private var cachedVisibleCalendarIds: Set<UUID> = []

    init(store: CalendarStore = FileCalendarStore()) {
        self.store = store
        loadPersistedData()
    }

    static func preview() -> CalendarViewModel {
        CalendarViewModel(
            store: InMemoryCalendarStore(
                snapshot: CalendarSeedData.previewSnapshot()
            )
        )
    }

    func calendar(for event: CalendarEvent) -> CalendarItem? {
        calendars.first { $0.id == event.calendarId }
    }

    func color(for event: CalendarEvent) -> Color {
        calendar(for: event)?.color.color ?? .blue
    }

    func toggleCalendarVisibility(_ calendar: CalendarItem) {
        if let index = calendars.firstIndex(where: { $0.id == calendar.id }) {
            calendars[index].isVisible.toggle()
            updateVisibleCalendarCache()
            saveCalendars()
        }
    }

    private func updateVisibleCalendarCache() {
        cachedVisibleCalendarIds = Set(calendars.filter { $0.isVisible }.map(\.id))
    }

    var visibleCalendarIds: Set<UUID> {
        cachedVisibleCalendarIds
    }

    var defaultCalendarId: UUID {
        calendars.first?.id ?? UUID()
    }

    var selectedEventId: UUID? {
        inspectorState?.eventID
    }

    var selectedEvent: CalendarEvent? {
        guard let selectedEventId else { return nil }
        return events.first { $0.id == selectedEventId }
    }

    var isEditingEvent: Bool {
        inspectorState?.isEditing ?? false
    }

    var isInspectorPresented: Bool {
        inspectorState != nil
    }

    func addEvent(_ event: CalendarEvent) {
        events.append(event)
        saveEvents()
    }

    func updateEvent(_ event: CalendarEvent) {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
            if !isPendingNewEvent(event.id) {
                saveEvents()
            }
        }
    }

    func deleteEvent(_ event: CalendarEvent) {
        events.removeAll { $0.id == event.id }
        if selectedEventId == event.id {
            closeInspector()
        }
        saveEvents()
    }

    func selectEvent(_ event: CalendarEvent) {
        if isPendingNewEvent(event.id) {
            inspectorState = .create(eventID: event.id)
            return
        }

        discardPendingNewEventIfNeeded(except: event.id)
        inspectorState = .view(eventID: event.id)
    }

    func startEditingSelectedEvent() {
        guard let selectedEvent else { return }
        inspectorState = .edit(eventID: selectedEvent.id)
    }

    func createNewEvent(referenceDate: Date? = nil) {
        let defaultDates = defaultDatesForNewEvent(referenceDate: referenceDate ?? selectedDate)
        createDraftEvent(
            startDate: defaultDates.start,
            endDate: defaultDates.end
        )
    }

    func createNewEvent(at startDate: Date, duration: TimeInterval = 3600) {
        createDraftEvent(
            startDate: startDate,
            endDate: adjustedEndDate(for: startDate, duration: duration)
        )
    }

    func updatePendingNewEvent(startDate: Date, endDate: Date) {
        let normalizedRange = normalizedTimeRange(
            startDate: startDate,
            endDate: endDate
        )

        if case .create(let eventID) = inspectorState,
           let index = events.firstIndex(where: { $0.id == eventID }) {
            events[index].startDate = normalizedRange.start
            events[index].endDate = normalizedRange.end
            events[index].isAllDay = false
            selectedDate = normalizedRange.start
            return
        }

        createDraftEvent(
            startDate: normalizedRange.start,
            endDate: normalizedRange.end
        )
    }

    func closeInspector() {
        discardPendingNewEventIfNeeded()
        inspectorState = nil
    }

    func clearSelection() {
        closeInspector()
    }

    func completeEditing(with event: CalendarEvent, isNewEvent: Bool) {
        if isNewEvent {
            if let index = events.firstIndex(where: { $0.id == event.id }) {
                events[index] = event
            } else {
                events.append(event)
            }
            saveEvents()
        } else {
            updateEvent(event)
        }

        inspectorState = .view(eventID: event.id)
    }

    func applyInspectorChanges(_ event: CalendarEvent) {
        if isPendingNewEvent(event.id) {
            if let index = events.firstIndex(where: { $0.id == event.id }) {
                events[index] = event
            } else {
                events.append(event)
            }

            if !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                saveEvents()
                inspectorState = .view(eventID: event.id)
            }
            return
        }

        updateEvent(event)
    }

    func discardEditing() {
        guard let state = inspectorState else { return }

        switch state {
        case .create(let eventID):
            events.removeAll { $0.id == eventID }
            inspectorState = nil
        case .edit(let eventID):
            inspectorState = .view(eventID: eventID)
        case .view:
            break
        }
    }

    func defaultDatesForNewEvent(referenceDate: Date? = nil) -> (start: Date, end: Date) {
        let referenceDate = referenceDate ?? selectedDate
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: referenceDate)

        let currentHour = calendar.component(.hour, from: Date())
        let startHour = calendar.isDateInToday(referenceDate) ? max(currentHour, 8) : 9
        let startDate = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: dayStart) ?? referenceDate
        let endDate = calendar.date(byAdding: .hour, value: 1, to: startDate) ?? startDate.addingTimeInterval(3600)
        return (startDate, endDate)
    }

    func defaultDurationForQuickCreate(at startDate: Date) -> TimeInterval {
        let calendar = Calendar.current
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: startDate))
            ?? startDate.addingTimeInterval(24 * 3600)
        let remainingTime = nextDayStart.timeIntervalSince(startDate)
        return max(15 * 60, min(3600, remainingTime))
    }

    func moveToNextPeriod() {
        switch viewMode {
        case .day:
            selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        case .week:
            selectedDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: selectedDate) ?? selectedDate
        case .month:
            selectedDate = Calendar.current.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
        case .year:
            selectedDate = Calendar.current.date(byAdding: .year, value: 1, to: selectedDate) ?? selectedDate
        }
    }

    func moveToPreviousPeriod() {
        switch viewMode {
        case .day:
            selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        case .week:
            selectedDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: selectedDate) ?? selectedDate
        case .month:
            selectedDate = Calendar.current.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
        case .year:
            selectedDate = Calendar.current.date(byAdding: .year, value: -1, to: selectedDate) ?? selectedDate
        }
    }

    func moveToToday() {
        selectedDate = Date()
    }

    func events(for date: Date) -> [CalendarEvent] {
        let calendar = Calendar.current
        return events.filter { event in
            visibleCalendarIds.contains(event.calendarId) &&
            (calendar.isDate(event.startDate, inSameDayAs: date) ||
             (event.startDate < date && event.endDate > date))
        }.sorted { $0.startDate < $1.startDate }
    }

    func events(in dateRange: ClosedRange<Date>) -> [CalendarEvent] {
        events.filter { event in
            visibleCalendarIds.contains(event.calendarId) &&
            event.startDate >= dateRange.lowerBound && event.startDate <= dateRange.upperBound
        }.sorted { $0.startDate < $1.startDate }
    }

    private func saveEvents() {
        do {
            try store.saveEvents(events)
        } catch {
            storageError = IdentifiableMessage(
                title: "Ошибка сохранения",
                message: error.localizedDescription
            )
        }
    }

    private func saveCalendars() {
        do {
            try store.saveCalendars(calendars)
        } catch {
            storageError = IdentifiableMessage(
                title: "Ошибка сохранения",
                message: error.localizedDescription
            )
        }
    }

    private func loadPersistedData() {
        do {
            let loadedCalendars = try store.loadCalendars()
            calendars = loadedCalendars.isEmpty ? CalendarSeedData.defaultCalendars() : loadedCalendars
            events = try store.loadEvents()
            updateVisibleCalendarCache()
            ensureLegalicCalendarExists()

            if loadedCalendars.isEmpty {
                saveCalendars()
            }
        } catch {
            calendars = CalendarSeedData.defaultCalendars()
            events = []
            updateVisibleCalendarCache()
            ensureLegalicCalendarExists()
            storageError = IdentifiableMessage(
                title: "Ошибка загрузки",
                message: error.localizedDescription
            )
        }
    }

    func ensureLegalicCalendarExists() {
        let id = LegalicCalendarConfiguration.stableCalendarId
        if let idx = calendars.firstIndex(where: { $0.id == id }) {
            if !calendars[idx].isVisible {
                calendars[idx].isVisible = true
                updateVisibleCalendarCache()
                saveCalendars()
                LegalicLogger.line("ensureLegalicCalendarExists: календарь LEGALIC был скрыт — снова включён показ")
            }
            return
        }
        calendars.append(
            CalendarItem(
                id: id,
                name: LegalicCalendarConfiguration.displayName,
                color: .purple,
                isVisible: true,
                accountName: "LEGALIC"
            )
        )
        updateVisibleCalendarCache()
        saveCalendars()
    }

    func visibleCalendarDateRange() -> ClosedRange<Date> {
        let calendar = Calendar.current
        let date = selectedDate
        switch viewMode {
        case .day:
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-1) ?? date
            return start ... end
        case .week:
            if let interval = calendar.dateInterval(of: .weekOfYear, for: date) {
                return interval.start ... interval.end.addingTimeInterval(-1)
            }
            return fallbackVisibleCalendarRange(around: date)
        case .month:
            if let interval = calendar.dateInterval(of: .month, for: date) {
                return interval.start ... interval.end.addingTimeInterval(-1)
            }
            return fallbackVisibleCalendarRange(around: date)
        case .year:
            if let interval = calendar.dateInterval(of: .year, for: date) {
                return interval.start ... interval.end.addingTimeInterval(-1)
            }
            return fallbackVisibleCalendarRange(around: date)
        }
    }

    private func fallbackVisibleCalendarRange(around date: Date) -> ClosedRange<Date> {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -14, to: date) ?? date
        let end = calendar.date(byAdding: .day, value: 14, to: date) ?? date
        return start ... end
    }

    private func legalicImportOverlapsVisibleRange(_ imp: LegalicTaskImport, range uiRange: ClosedRange<Date>) -> Bool {
        imp.startDate <= uiRange.upperBound && imp.endDate >= uiRange.lowerBound
    }

    private func focusCalendarOnLegalicImportsIfNeeded(_ imports: [LegalicTaskImport]) {
        guard !imports.isEmpty else { return }
        let uiRange = visibleCalendarDateRange()
        if imports.contains(where: { legalicImportOverlapsVisibleRange($0, range: uiRange) }) {
            return
        }
        let calendar = Calendar.current
        guard let minStart = imports.map(\.startDate).min() else { return }
        selectedDate = calendar.startOfDay(for: minStart)
        LegalicLogger.line(
            "syncTasksFromLegalic: в текущем \(viewMode.rawValue) (\(legalicRangeLogFormatter.string(from: uiRange.lowerBound)) — \(legalicRangeLogFormatter.string(from: uiRange.upperBound))) нет импортированных задач — выбран день первой: \(legalicRangeLogFormatter.string(from: selectedDate))"
        )
    }

    func syncTasksFromLegalic() async {
        LegalicLogger.line("syncTasksFromLegalic: кнопка нажата, viewMode=\(viewMode.rawValue), selectedDate=\(selectedDate)")
        legalicSyncError = nil
        let legalic = LegalicService.shared
        guard legalic.hasCredentials else {
            LegalicLogger.line("syncTasksFromLegalic: нет apiKey/apiSecret — выход")
            legalicSyncError = IdentifiableMessage(
                title: "LEGALIC",
                message: "Укажите API Key и API Secret в настройках приложения (⌘,)."
            )
            return
        }

        isLegalicSyncing = true
        defer {
            isLegalicSyncing = false
            LegalicLogger.line("syncTasksFromLegalic: конец (isLegalicSyncing=false)")
        }

        do {
            let visibleRange = legalic.syncTasksInVisibleRangeOnly ? visibleCalendarDateRange() : nil
            let tasksURL = legalic.tasksFetchURL(visibleDateRange: visibleRange)

            if let visibleRange {
                LegalicLogger.line(
                    "syncTasksFromLegalic: видимый период (локально, \(TimeZone.current.identifier)): \(legalicRangeLogFormatter.string(from: visibleRange.lowerBound)) — \(legalicRangeLogFormatter.string(from: visibleRange.upperBound))"
                )
                LegalicLogger.line("syncTasksFromLegalic: тот же интервал в UTC для API: \(visibleRange.lowerBound) … \(visibleRange.upperBound)")
            } else {
                LegalicLogger.line("syncTasksFromLegalic: полная выгрузка (без from/to)")
            }
            LegalicLogger.line(
                "syncTasksFromLegalic: базовый URL задач (к нему добавятся page/per_page): \(tasksURL.absoluteString), страниц ≤\(legalic.taskSyncMaxPages), per_page=\(legalic.taskSyncPerPage)"
            )

            let imports = try await LegalicAPIClient.shared.fetchTasks(
                baseURL: legalic.resolvedBaseURL,
                tasksURL: tasksURL,
                apiKey: legalic.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                apiSecret: legalic.apiSecret.trimmingCharacters(in: .whitespacesAndNewlines),
                maxPages: legalic.taskSyncMaxPages,
                perPage: legalic.taskSyncPerPage
            )
            LegalicLogger.line("syncTasksFromLegalic: получено задач: \(imports.count)")
            ensureLegalicCalendarExists()
            let calendarId = LegalicCalendarConfiguration.stableCalendarId
            let tag = LegalicCalendarConfiguration.sourceTag

            let beforeCount = events.filter { $0.calendarId == calendarId }.count
            if let visibleRange {
                events.removeAll { event in
                    guard event.calendarId == calendarId else { return false }
                    return visibleRange.contains(event.startDate)
                }
            } else {
                events.removeAll { $0.calendarId == calendarId }
            }
            let removed = beforeCount - events.filter { $0.calendarId == calendarId }.count
            LegalicLogger.line("syncTasksFromLegalic: удалено событий в календаре LEGALIC: \(removed) (было \(beforeCount))")

            for task in imports {
                events.append(
                    CalendarEvent(
                        title: task.title,
                        startDate: task.startDate,
                        endDate: task.endDate,
                        isAllDay: task.isAllDay,
                        notes: task.notes,
                        location: "",
                        calendarId: calendarId,
                        externalId: task.id,
                        externalSource: tag
                    )
                )
            }
            focusCalendarOnLegalicImportsIfNeeded(imports)
            saveEvents()
            LegalicLogger.line("syncTasksFromLegalic: сохранено, всего событий в модели: \(events.count)")
        } catch {
            LegalicLogger.line("syncTasksFromLegalic: ОШИБКА — \(error.localizedDescription)")
            legalicSyncError = IdentifiableMessage(
                title: "LEGALIC",
                message: error.localizedDescription
            )
        }
    }

    private func createDraftEvent(startDate: Date, endDate: Date) {
        discardPendingNewEventIfNeeded()
        selectedDate = startDate

        let draftEvent = CalendarEvent(
            title: "",
            startDate: startDate,
            endDate: endDate,
            calendarId: defaultCalendarId
        )

        events.append(draftEvent)
        inspectorState = .create(eventID: draftEvent.id)
    }

    private func normalizedTimeRange(startDate: Date, endDate: Date) -> (start: Date, end: Date) {
        let minimumDuration: TimeInterval = 15 * 60
        let start = min(startDate, endDate)
        let maxEnd = adjustedEndDate(for: start, duration: 24 * 3600)
        let candidateEnd = max(max(startDate, endDate), start.addingTimeInterval(minimumDuration))
        return (start, min(candidateEnd, maxEnd))
    }

    private func adjustedEndDate(for startDate: Date, duration: TimeInterval) -> Date {
        let calendar = Calendar.current
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: startDate))
            ?? startDate.addingTimeInterval(24 * 3600)
        let minimumEndDate = startDate.addingTimeInterval(15 * 60)
        let candidateEndDate = startDate.addingTimeInterval(duration)
        return min(max(candidateEndDate, minimumEndDate), nextDayStart)
    }

    private func discardPendingNewEventIfNeeded(except eventIDToKeep: UUID? = nil) {
        guard case .create(let eventID) = inspectorState else { return }
        guard eventID != eventIDToKeep else { return }
        events.removeAll { $0.id == eventID }
    }

    private func isPendingNewEvent(_ eventID: UUID) -> Bool {
        guard case .create(let pendingEventID) = inspectorState else { return false }
        return pendingEventID == eventID
    }
}
