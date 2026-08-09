import Combine
import SwiftUI

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published var events: [CalendarEvent] = []
    @Published var calendars: [CalendarItem] = []
    @Published var selectedDate: Date = Date()
    @Published var viewMode: ViewMode = .day
    @Published var inspectorState: EventInspectorState?
    @Published var storageError: IdentifiableMessage?
    @Published private(set) var syncingProviderIDs: Set<ProviderID> = []
    @Published var legalicSyncError: IdentifiableMessage?
    @Published private(set) var pendingDeletions: [PendingEventDeletion] = []

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
        calendars.first(where: \.isWritable)?.id ?? calendars.first?.id ?? UUID()
    }

    var isSyncing: Bool { !syncingProviderIDs.isEmpty }

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
        events.append(preparedLocalChange(event, replacing: nil))
        saveEvents()
    }

    func updateEvent(_ event: CalendarEvent) {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            let previous = events[index]
            guard canEdit(previous) else { return }
            events[index] = preparedLocalChange(event, replacing: previous)
            if !isPendingNewEvent(event.id) {
                saveEvents()
            }
        }
    }

    func deleteEvent(_ event: CalendarEvent) {
        guard canEdit(event) else { return }
        enqueueDeletionIfNeeded(for: event)
        events.removeAll { $0.id == event.id }
        if selectedEventId == event.id {
            closeInspector()
        }
        saveEvents()
        savePendingDeletions()
    }

    func canEdit(_ event: CalendarEvent) -> Bool {
        calendar(for: event)?.isWritable ?? true
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
                events[index] = preparedLocalChange(event, replacing: events[index])
            } else {
                events.append(preparedLocalChange(event, replacing: nil))
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
                events[index] = preparedLocalChange(event, replacing: events[index])
            } else {
                events.append(preparedLocalChange(event, replacing: nil))
            }

            if !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                saveEvents()
                inspectorState = .view(eventID: event.id)
            }
            return
        }

        updateEvent(event)
    }

    private func preparedLocalChange(_ event: CalendarEvent, replacing previous: CalendarEvent?) -> CalendarEvent {
        var changed = event
        guard let destination = calendars.first(where: { $0.id == event.calendarId }),
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
              let sourceCalendar = calendars.first(where: { $0.id == event.calendarId }),
              sourceCalendar.isWritable
        else { return }
        let ref = RemoteEventRef(
            providerID: providerID,
            remoteCalendarID: remoteCalendarID,
            remoteEventID: remoteEventID
        )
        guard !pendingDeletions.contains(where: { $0.remoteRef == ref }) else { return }
        pendingDeletions.append(PendingEventDeletion(remoteRef: ref, etag: event.externalETag))
        savePendingDeletions()
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

    private func savePendingDeletions() {
        do {
            try store.savePendingDeletions(pendingDeletions)
        } catch {
            storageError = IdentifiableMessage(
                title: "Ошибка сохранения очереди синхронизации",
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
            pendingDeletions = try store.loadPendingDeletions()
            updateVisibleCalendarCache()

            if loadedCalendars.isEmpty {
                saveCalendars()
            }
        } catch {
            calendars = CalendarSeedData.defaultCalendars()
            events = []
            pendingDeletions = []
            updateVisibleCalendarCache()
            storageError = IdentifiableMessage(
                title: "Ошибка загрузки",
                message: error.localizedDescription
            )
        }
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

    func syncAllProviders() async {
        legalicSyncError = nil
        let providers = ProviderRegistry.shared.enabledProviders
        guard !providers.isEmpty else {
            legalicSyncError = IdentifiableMessage(
                title: "Синхронизация",
                message: "Включите хотя бы один аккаунт в настройках."
            )
            return
        }
        var failures: [String] = []
        for provider in providers {
            do {
                try await synchronize(provider)
            } catch {
                failures.append("\(provider.displayName): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty {
            legalicSyncError = IdentifiableMessage(
                title: "Синхронизация завершена с ошибками",
                message: failures.joined(separator: "\n\n")
            )
        }
    }

    func sync(providerID: ProviderID) async {
        legalicSyncError = nil
        guard let provider = ProviderRegistry.shared.provider(providerID) else {
            legalicSyncError = IdentifiableMessage(
                title: "Синхронизация",
                message: ProviderError.unknownProvider(providerID).localizedDescription
            )
            return
        }
        do {
            try await synchronize(provider)
        } catch {
            legalicSyncError = IdentifiableMessage(
                title: provider.displayName,
                message: error.localizedDescription
            )
        }
    }

    private func synchronize(_ provider: any CalendarProvider) async throws {
        guard provider.isEnabled else { throw ProviderError.providerDisabled(provider.id) }
        syncingProviderIDs.insert(provider.id)
        defer { syncingProviderIDs.remove(provider.id) }

        let remoteCalendars = try await provider.listRemoteCalendars()
        mergeRemoteCalendars(remoteCalendars, provider: provider)

        for remoteCalendar in remoteCalendars {
            guard let localIndex = calendars.firstIndex(where: {
                $0.externalProvider == provider.id && $0.externalId == remoteCalendar.id
            }) else { continue }

            let requestedRange: ClosedRange<Date>? = provider.id == .legalic
                ? visibleCalendarDateRange()
                : nil
            var syncToken = calendars[localIndex].syncToken
            let batch: SyncBatch
            do {
                batch = try await fetchAllEvents(
                    provider: provider,
                    calendar: remoteCalendar,
                    dateRange: requestedRange,
                    syncToken: syncToken
                )
            } catch ProviderError.syncTokenExpired {
                syncToken = nil
                calendars[localIndex].syncToken = nil
                batch = try await fetchAllEvents(
                    provider: provider,
                    calendar: remoteCalendar,
                    dateRange: requestedRange,
                    syncToken: nil
                )
            }

            let deletionResolution = CalendarSyncMerger.resolveDeletionConflicts(
                in: batch,
                pendingDeletions: pendingDeletions
            )
            pendingDeletions = deletionResolution.pendingDeletions
            let resolvedBatch = deletionResolution.batch
            events = CalendarSyncMerger.merge(
                resolvedBatch,
                into: events,
                localCalendar: calendars[localIndex],
                dateRange: requestedRange
            )
            if let nextSyncToken = resolvedBatch.nextSyncToken {
                calendars[localIndex].syncToken = nextSyncToken
            }
            // Применённый batch и cursor сохраняем до исходящих операций.
            // Если push упадёт, следующий запуск продолжит с уже сохранённого
            // локального состояния, а dirty/outbox останутся для повтора.
            saveCalendars()
            saveEvents()
            savePendingDeletions()
        }

        // Сначала pull + LWW выше, и только затем push тех локальных
        // изменений, которые действительно победили конфликт.
        try await flushPendingDeletions(for: provider)
        try await flushPendingUpserts(for: provider, remoteCalendars: remoteCalendars)

        updateVisibleCalendarCache()
        saveCalendars()
        saveEvents()
        savePendingDeletions()
    }

    private func fetchAllEvents(
        provider: any CalendarProvider,
        calendar: RemoteCalendar,
        dateRange: ClosedRange<Date>?,
        syncToken: String?
    ) async throws -> SyncBatch {
        var pageToken: String?
        var allUpserts: [ParsedRemoteEvent] = []
        var allDeletes: [DeletedRemoteEvent] = []
        var nextSyncToken: String?
        var kind: SyncBatchKind = syncToken == nil ? .fullSnapshot : .incremental
        var coveredDateRange: ClosedRange<Date>?
        repeat {
            let page = try await provider.fetchEvents(
                calendar: calendar,
                request: SyncRequest(dateRange: dateRange, pageToken: pageToken, syncToken: syncToken)
            )
            allUpserts.append(contentsOf: page.upserts)
            allDeletes.append(contentsOf: page.deletes)
            pageToken = page.nextPageToken
            nextSyncToken = page.nextSyncToken ?? nextSyncToken
            kind = page.kind
            coveredDateRange = page.coveredDateRange
        } while pageToken != nil
        return SyncBatch(
            upserts: allUpserts,
            deletes: allDeletes,
            nextPageToken: nil,
            nextSyncToken: nextSyncToken,
            kind: kind,
            coveredDateRange: coveredDateRange
        )
    }

    private func mergeRemoteCalendars(_ remoteCalendars: [RemoteCalendar], provider: any CalendarProvider) {
        for remote in remoteCalendars {
            let color = EventColor.nearest(to: remote.colorHex, fallback: provider.id.defaultColor)
            if let index = calendars.firstIndex(where: {
                $0.externalProvider == provider.id && $0.externalId == remote.id
            }) {
                calendars[index].name = remote.title
                calendars[index].color = color
                calendars[index].accountName = provider.displayName
                calendars[index].isWritable = remote.isWritable
            } else {
                calendars.append(
                    CalendarItem(
                        name: remote.title,
                        color: color,
                        accountName: provider.displayName,
                        externalProvider: provider.id,
                        externalId: remote.id,
                        isWritable: remote.isWritable
                    )
                )
            }
        }
        updateVisibleCalendarCache()
        saveCalendars()
    }

    private func flushPendingDeletions(for provider: any CalendarProvider) async throws {
        let queued = pendingDeletions.filter { $0.remoteRef.providerID == provider.id }
        for deletion in queued {
            try await provider.pushDelete(deletion.remoteRef, etag: deletion.etag)
            pendingDeletions.removeAll { $0.id == deletion.id }
            savePendingDeletions()
        }
    }

    private func flushPendingUpserts(
        for provider: any CalendarProvider,
        remoteCalendars: [RemoteCalendar]
    ) async throws {
        let eventIDs = events.filter {
            $0.externalProvider == provider.id && $0.syncState == .pendingUpload
        }.map(\.id)
        for eventID in eventIDs {
            guard let index = events.firstIndex(where: { $0.id == eventID }),
                  let remoteCalendarID = events[index].externalCalendarId,
                  let remoteCalendar = remoteCalendars.first(where: { $0.id == remoteCalendarID })
            else { continue }
            if events[index].externalId == nil,
               events[index].pendingCreateRemoteId == nil {
                events[index].pendingCreateRemoteId = provider.proposedRemoteEventID(for: events[index])
                try persistEventsBeforePush()
            }
            let pushed = try await provider.pushUpsert(localEvent: events[index], to: remoteCalendar)
            guard let currentIndex = events.firstIndex(where: { $0.id == eventID }) else { continue }
            events[currentIndex].externalProvider = pushed.remoteRef.providerID
            events[currentIndex].externalCalendarId = pushed.remoteRef.remoteCalendarID
            events[currentIndex].externalId = pushed.remoteRef.remoteEventID
            events[currentIndex].externalETag = pushed.etag
            events[currentIndex].pendingCreateRemoteId = nil
            events[currentIndex].remoteUpdatedAt = pushed.updatedAt
            events[currentIndex].syncState = .clean
            saveEvents()
        }
    }

    private func persistEventsBeforePush() throws {
        do {
            try store.saveEvents(events)
        } catch {
            storageError = IdentifiableMessage(
                title: "Ошибка сохранения очереди синхронизации",
                message: error.localizedDescription
            )
            throw error
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
