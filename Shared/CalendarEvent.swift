import SwiftUI

struct CalendarEvent: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var notes: String
    var location: String
    var calendarId: UUID
    var externalId: String?
    var externalSource: String?

    init(
        id: UUID = UUID(),
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        notes: String = "",
        location: String = "",
        calendarId: UUID,
        externalId: String? = nil,
        externalSource: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.notes = notes
        self.location = location
        self.calendarId = calendarId
        self.externalId = externalId
        self.externalSource = externalSource
    }
}

enum EventColor: String, Codable, CaseIterable {
    case red = "red"
    case orange = "orange"
    case yellow = "yellow"
    case green = "green"
    case blue = "blue"
    case purple = "purple"
    case pink = "pink"
    case brown = "brown"

    var color: Color {
        switch self {
        case .red: return Color(red: 0.95, green: 0.6, blue: 0.6)
        case .orange: return Color(red: 0.95, green: 0.75, blue: 0.5)
        case .yellow: return Color(red: 0.95, green: 0.9, blue: 0.6)
        case .green: return Color(red: 0.7, green: 0.9, blue: 0.7)
        case .blue: return Color(red: 0.6, green: 0.8, blue: 0.95)
        case .purple: return Color(red: 0.8, green: 0.7, blue: 0.95)
        case .pink: return Color(red: 0.95, green: 0.7, blue: 0.85)
        case .brown: return Color(red: 0.8, green: 0.7, blue: 0.6)
        }
    }

    var displayName: String {
        switch self {
        case .red: return "Красный"
        case .orange: return "Оранжевый"
        case .yellow: return "Жёлтый"
        case .green: return "Зелёный"
        case .blue: return "Синий"
        case .purple: return "Фиолетовый"
        case .pink: return "Розовый"
        case .brown: return "Коричневый"
        }
    }
}

enum ViewMode: String, CaseIterable {
    case day = "День"
    case week = "Неделя"
    case month = "Месяц"
    case year = "Год"
}
