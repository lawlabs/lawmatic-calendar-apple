import Foundation

struct CalendarStoreSnapshot: Equatable {
    var calendars: [CalendarItem]
    var events: [CalendarEvent]
}

protocol CalendarStore {
    func loadCalendars() throws -> [CalendarItem]
    func saveCalendars(_ calendars: [CalendarItem]) throws
    func loadEvents() throws -> [CalendarEvent]
    func saveEvents(_ events: [CalendarEvent]) throws
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
}
