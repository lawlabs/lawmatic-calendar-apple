import Foundation

struct CalendarStoreSnapshot: Equatable {
    var calendars: [CalendarItem]
    var events: [CalendarEvent]
    var pendingDeletions: [PendingEventDeletion] = []
}

protocol CalendarStore: AnyObject {
    func loadCalendars() throws -> [CalendarItem]
    func saveCalendars(_ calendars: [CalendarItem]) throws
    func loadEvents() throws -> [CalendarEvent]
    func saveEvents(_ events: [CalendarEvent]) throws
    func loadPendingDeletions() throws -> [PendingEventDeletion]
    func savePendingDeletions(_ deletions: [PendingEventDeletion]) throws

    /// Обработчик ошибок отложенной записи (для хранилищ, которые пишут на
    /// диск в фоне и не могут бросить ошибку из `save*`).
    func setWriteErrorHandler(_ handler: @escaping @MainActor (Error) -> Void)
    /// Дождаться завершения отложенных записей (перед выходом из приложения).
    func waitForPendingWrites(timeout: TimeInterval)
}

extension CalendarStore {
    func setWriteErrorHandler(_ handler: @escaping @MainActor (Error) -> Void) {}
    func waitForPendingWrites(timeout: TimeInterval = 5) {}
}

final class InMemoryCalendarStore: CalendarStore {
    private var snapshot: CalendarStoreSnapshot

    init(snapshot: CalendarStoreSnapshot = CalendarStoreSnapshot(calendars: [], events: [])) {
        self.snapshot = snapshot
    }

    func loadCalendars() throws -> [CalendarItem] {
        snapshot.calendars
    }

    func saveCalendars(_ calendars: [CalendarItem]) throws {
        snapshot.calendars = calendars
    }

    func loadEvents() throws -> [CalendarEvent] {
        snapshot.events
    }

    func saveEvents(_ events: [CalendarEvent]) throws {
        snapshot.events = events
    }

    func loadPendingDeletions() throws -> [PendingEventDeletion] {
        snapshot.pendingDeletions
    }

    func savePendingDeletions(_ deletions: [PendingEventDeletion]) throws {
        snapshot.pendingDeletions = deletions
    }
}
