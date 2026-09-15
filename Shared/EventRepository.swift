import Foundation
import Observation
import SwiftUI

/// Локальные данные календаря: события, календари, очередь удалений —
/// плюс индексы для быстрых выборок и персистенция через `CalendarStore`.
///
/// Репозиторий не знает ни о выделении, ни о режимах просмотра, ни о
/// синхронизации: это источник истины для UI и для `CalendarSyncCoordinator`.
@Observable
@MainActor
final class EventRepository {
    var events: [CalendarEvent] = [] {
        didSet { updateEventIndex(from: oldValue) }
    }
    var calendars: [CalendarItem] = [] {
        didSet { rebuildCalendarIndex() }
    }
    var pendingDeletions: [PendingEventDeletion] = []
    var storageError: IdentifiableMessage?

    @ObservationIgnored private let store: CalendarStore
    @ObservationIgnored private let saveDebounce: Duration

    /// События, сгруппированные по началу календарного дня. Многодневное
    /// событие лежит во всех днях своего диапазона. Пересобирается при любом
    /// изменении `events`, чтобы `events(for:)` был O(1) на каждую ячейку.
    ///
    /// Индексы намеренно наблюдаемые: view, читающая `events(for:)`, зависит
    /// именно от них и перерисуется только при изменении данных, а не при
    /// смене выделения или режима.
    private var eventsByDay: [Date: [CalendarEvent]] = [:]
    private var calendarsByID: [UUID: CalendarItem] = [:]
    private var cachedVisibleCalendarIds: Set<UUID> = []

    enum SaveTarget: Hashable {
        case events, calendars, pendingDeletions
    }

    @ObservationIgnored private var pendingSaveTargets: Set<SaveTarget> = []
    @ObservationIgnored private var pendingSaveTask: Task<Void, Never>?

    /// - Parameter saveDebounce: задержка отложенного сохранения для
    ///   покомпонентных правок из инспектора. Дискретные действия (drag,
    ///   удаление, завершение редактирования, синк) сохраняются сразу.
    init(store: CalendarStore, saveDebounce: Duration = .milliseconds(400)) {
        self.store = store
        self.saveDebounce = saveDebounce
        loadPersistedData()
        store.setWriteErrorHandler { [weak self] error in
            self?.storageError = IdentifiableMessage(
                title: "Ошибка сохранения",
                message: error.localizedDescription
            )
        }
    }

    // MARK: - Индексы

    /// Обновляет индекс по дням после изменения `events`.
    ///
    /// Типичная правка — одно событие (drag, ввод в инспекторе, создание,
    /// удаление), а полная пересборка индекса на десятках тысяч событий стоит
    /// ~100 мс главного потока. Поэтому сначала ищем узкую разницу и правим
    /// только затронутые дни; полная пересборка — для массовых замен (синк).
    private func updateEventIndex(from oldValue: [CalendarEvent]) {
        let new = events
        if new.count == oldValue.count {
            // Правка на месте: одно или несколько событий с теми же позициями.
            var changed: [(old: CalendarEvent, new: CalendarEvent)] = []
            for index in new.indices where new[index] != oldValue[index] {
                changed.append((oldValue[index], new[index]))
                if changed.count > 8 { return rebuildEventIndex() }
            }
            for pair in changed {
                removeFromIndex(pair.old)
                insertIntoIndex(pair.new)
            }
            return
        }
        if new.count == oldValue.count + 1, let last = new.last, new.dropLast().elementsEqual(oldValue) {
            insertIntoIndex(last)
            return
        }
        if new.count == oldValue.count - 1,
           let removedIndex = oldValue.indices.first(where: { index in
               index >= new.count || new[index] != oldValue[index]
           }),
           new.elementsEqual(oldValue[..<removedIndex] + oldValue[(removedIndex + 1)...]) {
            removeFromIndex(oldValue[removedIndex])
            return
        }
        rebuildEventIndex()
    }

    private func rebuildEventIndex() {
        var index: [Date: [CalendarEvent]] = [:]
        index.reserveCapacity(events.count)

        for event in events {
            for day in Self.days(covering: event) {
                index[day, default: []].append(event)
            }
        }

        for key in index.keys {
            index[key]?.sort { $0.startDate < $1.startDate }
        }
        eventsByDay = index
    }

    private func insertIntoIndex(_ event: CalendarEvent) {
        for day in Self.days(covering: event) {
            var bucket = eventsByDay[day] ?? []
            let position = bucket.firstIndex { $0.startDate > event.startDate } ?? bucket.endIndex
            bucket.insert(event, at: position)
            eventsByDay[day] = bucket
        }
    }

    private func removeFromIndex(_ event: CalendarEvent) {
        for day in Self.days(covering: event) {
            guard var bucket = eventsByDay[day] else { continue }
            bucket.removeAll { $0.id == event.id }
            eventsByDay[day] = bucket.isEmpty ? nil : bucket
        }
    }

    /// Начала календарных дней, которые покрывает событие.
    /// Событие, заканчивающееся ровно в полночь, не относится к следующему дню.
    private static func days(covering event: CalendarEvent) -> [Date] {
        let calendar = Calendar.current
        let firstDay = calendar.startOfDay(for: event.startDate)
        var lastDay = calendar.startOfDay(for: max(event.endDate, event.startDate))
        if lastDay > firstDay, event.endDate == lastDay {
            lastDay = calendar.date(byAdding: .day, value: -1, to: lastDay) ?? firstDay
        }

        var days: [Date] = [firstDay]
        var day = firstDay
        while day < lastDay, days.count < 3_660 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            days.append(day)
        }
        return days
    }

    private func rebuildCalendarIndex() {
        calendarsByID = Dictionary(calendars.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        cachedVisibleCalendarIds = Set(calendars.filter { $0.isVisible }.map(\.id))
    }

    // MARK: - Выборки

    var visibleCalendarIds: Set<UUID> {
        cachedVisibleCalendarIds
    }

    func calendar(for event: CalendarEvent) -> CalendarItem? {
        calendarsByID[event.calendarId]
    }

    func calendar(withID id: UUID) -> CalendarItem? {
        calendarsByID[id]
    }

    func color(for event: CalendarEvent) -> Color {
        calendar(for: event)?.color.color ?? .blue
    }

    func event(withID id: UUID) -> CalendarEvent? {
        events.first { $0.id == id }
    }

    /// События дня с учётом видимости календарей, отсортированные по началу.
    /// Многодневные события включаются во все дни, которые они покрывают.
    func events(for date: Date) -> [CalendarEvent] {
        let day = Calendar.current.startOfDay(for: date)
        guard let bucket = eventsByDay[day] else { return [] }
        return bucket.filter { visibleCalendarIds.contains($0.calendarId) }
    }

    /// Есть ли у дня хотя бы одно видимое событие (без построения массива).
    func hasEvents(on date: Date) -> Bool {
        let day = Calendar.current.startOfDay(for: date)
        guard let bucket = eventsByDay[day] else { return false }
        return bucket.contains { visibleCalendarIds.contains($0.calendarId) }
    }

    /// Ближайшие `limit` событий, начинающихся не раньше `date`.
    func upcomingEvents(from date: Date = Date(), limit: Int = 5) -> [CalendarEvent] {
        var result: [CalendarEvent] = []
        result.reserveCapacity(limit)
        for event in events where event.startDate >= date && visibleCalendarIds.contains(event.calendarId) {
            if result.count < limit {
                result.append(event)
                result.sort { $0.startDate < $1.startDate }
            } else if let last = result.last, event.startDate < last.startDate {
                result[limit - 1] = event
                result.sort { $0.startDate < $1.startDate }
            }
        }
        return result
    }

    // MARK: - Персистенция

    func save(_ target: SaveTarget) {
        pendingSaveTargets.remove(target)
        do {
            switch target {
            case .events: try store.saveEvents(events)
            case .calendars: try store.saveCalendars(calendars)
            case .pendingDeletions: try store.savePendingDeletions(pendingDeletions)
            }
        } catch {
            storageError = IdentifiableMessage(
                title: target == .pendingDeletions ? "Ошибка сохранения очереди синхронизации" : "Ошибка сохранения",
                message: error.localizedDescription
            )
        }
    }

    /// Сохранить и пробросить ошибку — для мест, где без записи нельзя
    /// продолжать (например, перед push с клиентским id).
    func saveOrThrow(_ target: SaveTarget) throws {
        pendingSaveTargets.remove(target)
        do {
            switch target {
            case .events: try store.saveEvents(events)
            case .calendars: try store.saveCalendars(calendars)
            case .pendingDeletions: try store.savePendingDeletions(pendingDeletions)
            }
        } catch {
            storageError = IdentifiableMessage(
                title: "Ошибка сохранения очереди синхронизации",
                message: error.localizedDescription
            )
            throw error
        }
    }

    /// Отложенное сохранение: несколько правок подряд схлопываются в одну запись.
    func scheduleSave(_ target: SaveTarget) {
        pendingSaveTargets.insert(target)
        pendingSaveTask?.cancel()
        let delay = saveDebounce
        pendingSaveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.flushPendingSaves()
        }
    }

    /// Немедленно записать всё, что ждёт отложенного сохранения.
    func flushPendingSaves() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        let targets = pendingSaveTargets
        pendingSaveTargets = []
        for target in targets {
            save(target)
        }
    }

    var hasPendingSaves: Bool {
        !pendingSaveTargets.isEmpty
    }

    /// Перед завершением приложения: записать всё отложенное и дождаться диска.
    func prepareForTermination() {
        flushPendingSaves()
        store.waitForPendingWrites(timeout: 5)
    }

    private func loadPersistedData() {
        do {
            let loadedCalendars = try store.loadCalendars()
            calendars = loadedCalendars.isEmpty ? CalendarSeedData.defaultCalendars() : loadedCalendars
            events = try store.loadEvents()
            pendingDeletions = try store.loadPendingDeletions()

            if loadedCalendars.isEmpty {
                save(.calendars)
            }
        } catch {
            calendars = CalendarSeedData.defaultCalendars()
            events = []
            pendingDeletions = []
            storageError = IdentifiableMessage(
                title: "Ошибка загрузки",
                message: error.localizedDescription
            )
        }
    }
}
