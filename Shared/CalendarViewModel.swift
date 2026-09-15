import Foundation
import Observation
import SwiftUI

/// Состояние интерфейса календаря: выбранная дата, режим, выделение и
/// инспектор, операции редактирования событий и undo.
///
/// Данные живут в `EventRepository`, синхронизация — в
/// `CalendarSyncCoordinator`; VM пробрасывает их наружу, чтобы view работали
/// с одним объектом.
@Observable
@MainActor
final class CalendarViewModel {
    var selectedDate: Date = Date()
    var viewMode: ViewMode = .day
    var inspectorState: EventInspectorState?

    let repository: EventRepository
    let sync: CalendarSyncCoordinator

    /// Менеджер отмены окна; подключается view через `.environment(\.undoManager)`.
    @ObservationIgnored weak var undoManager: UndoManager?

    /// Как сохранять изменение: сразу (дискретное действие) или отложенно
    /// (покомпонентный ввод в инспекторе, где каждое нажатие — новое значение).
    enum Persistence {
        case immediate
        case debounced
    }

    /// - Parameters:
    ///   - store: хранилище локальных данных.
    ///   - providers: источник провайдеров синхронизации (в тестах — mock).
    ///   - saveDebounce: задержка отложенного сохранения правок из инспектора.
    init(
        store: CalendarStore = FileCalendarStore(),
        providers: (any CalendarProviderResolving)? = nil,
        saveDebounce: Duration = .milliseconds(400)
    ) {
        let repository = EventRepository(store: store, saveDebounce: saveDebounce)
        self.repository = repository
        self.sync = CalendarSyncCoordinator(
            repository: repository,
            providers: providers ?? ProviderRegistry.shared
        )
    }

    static func preview() -> CalendarViewModel {
        CalendarViewModel(
            store: InMemoryCalendarStore(
                snapshot: CalendarSeedData.previewSnapshot()
            )
        )
    }

    // MARK: - Проброс данных

    var events: [CalendarEvent] { repository.events }
    var calendars: [CalendarItem] { repository.calendars }
    var pendingDeletions: [PendingEventDeletion] { repository.pendingDeletions }
    var visibleCalendarIds: Set<UUID> { repository.visibleCalendarIds }

    var storageError: IdentifiableMessage? {
        get { repository.storageError }
        set { repository.storageError = newValue }
    }

    func calendar(for event: CalendarEvent) -> CalendarItem? { repository.calendar(for: event) }
    func color(for event: CalendarEvent) -> Color { repository.color(for: event) }
    func events(for date: Date) -> [CalendarEvent] { repository.events(for: date) }
    func hasEvents(on date: Date) -> Bool { repository.hasEvents(on: date) }
    func upcomingEvents(from date: Date = Date(), limit: Int = 5) -> [CalendarEvent] {
        repository.upcomingEvents(from: date, limit: limit)
    }

    var hasPendingSaves: Bool { repository.hasPendingSaves }
    func flushPendingSaves() { repository.flushPendingSaves() }
    func prepareForTermination() { repository.prepareForTermination() }

    // MARK: - Проброс синхронизации

    var isSyncing: Bool { sync.isSyncing }
    var syncProgressText: String? { sync.progressText }
    var pendingMassDeletion: CalendarSyncCoordinator.MassDeletionRequest? { sync.pendingMassDeletion }
    var syncingProviderIDs: Set<ProviderID> { sync.syncingProviderIDs }
    var lastSuccessfulSyncDate: Date? { sync.lastSuccessfulSyncDate }

    var syncError: IdentifiableMessage? {
        get { sync.syncError }
        set { sync.syncError = newValue }
    }

    func syncAllProviders() async { await sync.syncAllProviders() }
    func sync(providerID: ProviderID) async { await sync.sync(providerID: providerID) }
    func startPeriodicSync() { sync.startPeriodicSync() }
    func handleDidBecomeActive() { sync.handleDidBecomeActive() }

    // MARK: - Календари

    func toggleCalendarVisibility(_ calendar: CalendarItem) {
        if let index = repository.calendars.firstIndex(where: { $0.id == calendar.id }) {
            repository.calendars[index].isVisible.toggle()
            repository.save(.calendars)
        }
    }

    var defaultCalendarId: UUID {
        calendars.first(where: \.isWritable)?.id ?? calendars.first?.id ?? UUID()
    }

    // MARK: - Выделение

    var selectedEventId: UUID? {
        inspectorState?.eventID
    }

    var selectedEvent: CalendarEvent? {
        guard let selectedEventId else { return nil }
        return repository.event(withID: selectedEventId)
    }

    var isEditingEvent: Bool {
        inspectorState?.isEditing ?? false
    }

    var isInspectorPresented: Bool {
        inspectorState != nil
    }

    func selectEvent(_ event: CalendarEvent) {
        if isPendingNewEvent(event.id) {
            inspectorState = .create(eventID: event.id)
            return
        }

        flushPendingSaves()
        discardPendingNewEventIfNeeded(except: event.id)
        inspectorState = .view(eventID: event.id)
    }

    func startEditingSelectedEvent() {
        guard let selectedEvent else { return }
        inspectorState = .edit(eventID: selectedEvent.id)
    }

    func closeInspector() {
        flushPendingSaves()
        discardPendingNewEventIfNeeded()
        inspectorState = nil
    }

    func clearSelection() {
        closeInspector()
    }

    func discardEditing() {
        guard let state = inspectorState else { return }

        switch state {
        case .create(let eventID):
            repository.events.removeAll { $0.id == eventID }
            inspectorState = nil
        case .edit(let eventID):
            flushPendingSaves()
            inspectorState = .view(eventID: eventID)
        case .view:
            break
        }
    }

    // MARK: - CRUD событий

    func canEdit(_ event: CalendarEvent) -> Bool {
        !event.isReadOnly && (calendar(for: event)?.isWritable ?? true)
    }

    func addEvent(_ event: CalendarEvent) {
        repository.events.append(preparedLocalChange(event, replacing: nil))
        repository.save(.events)
    }

    func updateEvent(_ event: CalendarEvent, persistence: Persistence = .immediate) {
        guard let index = repository.events.firstIndex(where: { $0.id == event.id }) else { return }
        let previous = repository.events[index]
        guard canEdit(previous) else { return }
        repository.events[index] = preparedLocalChange(event, replacing: previous)
        guard !isPendingNewEvent(event.id) else { return }

        switch persistence {
        case .immediate:
            repository.save(.events)
            registerUndo(actionName: "Изменение события") { viewModel in
                viewModel.updateEvent(previous)
            }
        case .debounced:
            repository.scheduleSave(.events)
        }
    }

    func deleteEvent(_ event: CalendarEvent) {
        guard canEdit(event) else { return }
        let wasDraft = isPendingNewEvent(event.id)
        let index = repository.events.firstIndex(where: { $0.id == event.id })
        guard let stored = index.map({ repository.events[$0] }) else { return }
        enqueueDeletionIfNeeded(for: stored)
        repository.events.removeAll { $0.id == event.id }
        if selectedEventId == event.id {
            closeInspector()
        }
        repository.save(.events)
        repository.save(.pendingDeletions)
        if !wasDraft {
            registerUndo(actionName: "Удаление события") { viewModel in
                viewModel.restoreDeletedEvent(stored, at: index ?? viewModel.events.count)
            }
        }
    }

    /// Удалить выбранное событие (команда меню / ⌘⌫).
    func deleteSelectedEvent() {
        guard let selectedEvent else { return }
        deleteEvent(selectedEvent)
    }

    /// Вернуть удалённое событие (undo). Если tombstone ещё не ушёл на сервер,
    /// он снимается и событие возвращается как было; иначе оно будет
    /// загружено заново как новое.
    private func restoreDeletedEvent(_ event: CalendarEvent, at index: Int) {
        guard !repository.events.contains(where: { $0.id == event.id }) else { return }
        var restored = event
        if let providerID = event.externalProvider,
           let remoteCalendarID = event.externalCalendarId,
           let remoteEventID = event.externalId {
            let ref = RemoteEventRef(providerID: providerID, remoteCalendarID: remoteCalendarID, remoteEventID: remoteEventID)
            if repository.pendingDeletions.contains(where: { $0.remoteRef == ref }) {
                repository.pendingDeletions.removeAll { $0.remoteRef == ref }
                repository.save(.pendingDeletions)
            } else {
                restored = preparedLocalChange(event, replacing: nil)
            }
        }
        repository.events.insert(restored, at: min(max(0, index), repository.events.count))
        repository.save(.events)
        inspectorState = .view(eventID: restored.id)
        registerUndo(actionName: "Удаление события") { viewModel in
            viewModel.deleteEvent(restored)
        }
    }

    private func registerUndo(actionName: String, _ handler: @escaping @MainActor (CalendarViewModel) -> Void) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { handler(target) }
        }
        undoManager.setActionName(actionName)
    }

    // MARK: - Создание и черновики

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
           let index = repository.events.firstIndex(where: { $0.id == eventID }) {
            repository.events[index].startDate = normalizedRange.start
            repository.events[index].endDate = normalizedRange.end
            repository.events[index].isAllDay = false
            selectedDate = normalizedRange.start
            return
        }

        createDraftEvent(
            startDate: normalizedRange.start,
            endDate: normalizedRange.end
        )
    }

    func completeEditing(with event: CalendarEvent, isNewEvent: Bool) {
        if isNewEvent {
            if let index = repository.events.firstIndex(where: { $0.id == event.id }) {
                repository.events[index] = preparedLocalChange(event, replacing: repository.events[index])
            } else {
                repository.events.append(preparedLocalChange(event, replacing: nil))
            }
            repository.save(.events)
            registerUndo(actionName: "Создание события") { viewModel in
                if let created = viewModel.repository.event(withID: event.id) {
                    viewModel.deleteEvent(created)
                }
            }
        } else {
            updateEvent(event)
        }

        inspectorState = .view(eventID: event.id)
    }

    func applyInspectorChanges(_ event: CalendarEvent) {
        if isPendingNewEvent(event.id) {
            if let index = repository.events.firstIndex(where: { $0.id == event.id }) {
                repository.events[index] = preparedLocalChange(event, replacing: repository.events[index])
            } else {
                repository.events.append(preparedLocalChange(event, replacing: nil))
            }

            if !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                repository.save(.events)
                inspectorState = .view(eventID: event.id)
                registerUndo(actionName: "Создание события") { viewModel in
                    if let created = viewModel.repository.event(withID: event.id) {
                        viewModel.deleteEvent(created)
                    }
                }
            }
            return
        }

        updateEvent(event, persistence: .debounced)
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

        repository.events.append(draftEvent)
        inspectorState = .create(eventID: draftEvent.id)
    }

    private func discardPendingNewEventIfNeeded(except eventIDToKeep: UUID? = nil) {
        guard case .create(let eventID) = inspectorState else { return }
        guard eventID != eventIDToKeep else { return }
        repository.events.removeAll { $0.id == eventID }
    }

    private func isPendingNewEvent(_ eventID: UUID) -> Bool {
        guard case .create(let pendingEventID) = inspectorState else { return false }
        return pendingEventID == eventID
    }

    // MARK: - Метаданные синхронизации локальных правок

    private func preparedLocalChange(_ event: CalendarEvent, replacing previous: CalendarEvent?) -> CalendarEvent {
        var changed = event
        guard let destination = repository.calendar(withID: event.calendarId),
              let providerID = destination.externalProvider,
              let remoteCalendarID = destination.externalId
        else {
            if let previous { enqueueDeletionIfNeeded(for: previous) }
            changed.externalId = nil
            changed.externalProvider = nil
            changed.externalCalendarId = nil
            changed.externalETag = nil
            changed.pendingCreateRemoteId = nil
            changed.remoteUpdatedAt = nil
            changed.syncState = .clean
            return changed
        }

        guard destination.isWritable else { return previous ?? changed }
        let isSameRemoteEvent = previous?.externalProvider == providerID &&
            previous?.externalCalendarId == remoteCalendarID
        if !isSameRemoteEvent, let previous { enqueueDeletionIfNeeded(for: previous) }

        changed.externalProvider = providerID
        changed.externalCalendarId = remoteCalendarID
        changed.externalId = isSameRemoteEvent ? previous?.externalId : nil
        changed.externalETag = isSameRemoteEvent ? previous?.externalETag : nil
        changed.pendingCreateRemoteId = isSameRemoteEvent ? previous?.pendingCreateRemoteId : nil
        changed.remoteUpdatedAt = isSameRemoteEvent ? previous?.remoteUpdatedAt : nil
        changed.localUpdatedAt = Date()
        changed.syncState = .pendingUpload
        return changed
    }

    private func enqueueDeletionIfNeeded(for event: CalendarEvent) {
        guard let providerID = event.externalProvider,
              let remoteCalendarID = event.externalCalendarId,
              let remoteEventID = event.externalId,
              let sourceCalendar = repository.calendar(withID: event.calendarId),
              sourceCalendar.isWritable
        else { return }
        let ref = RemoteEventRef(
            providerID: providerID,
            remoteCalendarID: remoteCalendarID,
            remoteEventID: remoteEventID
        )
        guard !repository.pendingDeletions.contains(where: { $0.remoteRef == ref }) else { return }
        repository.pendingDeletions.append(PendingEventDeletion(remoteRef: ref, etag: event.externalETag))
        repository.save(.pendingDeletions)
    }

    // MARK: - Даты по умолчанию

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

    // MARK: - Навигация

    func moveToNextPeriod() {
        move(by: 1)
    }

    func moveToPreviousPeriod() {
        move(by: -1)
    }

    func moveToToday() {
        selectedDate = Date()
    }

    private func move(by value: Int) {
        let component: Calendar.Component
        switch viewMode {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        }
        selectedDate = Calendar.current.date(byAdding: component, value: value, to: selectedDate) ?? selectedDate
    }

    func visibleCalendarDateRange() -> ClosedRange<Date> {
        let calendar = Calendar.current
        let date = selectedDate
        let component: Calendar.Component
        switch viewMode {
        case .day:
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-1) ?? date
            return start ... end
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        }
        if let interval = calendar.dateInterval(of: component, for: date) {
            return interval.start ... interval.end.addingTimeInterval(-1)
        }
        let start = calendar.date(byAdding: .day, value: -14, to: date) ?? date
        let end = calendar.date(byAdding: .day, value: 14, to: date) ?? date
        return start ... end
    }
}
