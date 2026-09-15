import SwiftUI

struct CalendarEvent: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var notes: String
    var location: String
    var calendarId: UUID
    var externalId: String?
    var externalProvider: ProviderID?
    var externalCalendarId: String?
    var externalETag: String?
    var pendingCreateRemoteId: String?
    var localUpdatedAt: Date
    var remoteUpdatedAt: Date?
    var syncState: EventSyncState

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
        externalProvider: ProviderID? = nil,
        externalCalendarId: String? = nil,
        externalETag: String? = nil,
        pendingCreateRemoteId: String? = nil,
        localUpdatedAt: Date = Date(),
        remoteUpdatedAt: Date? = nil,
        syncState: EventSyncState = .clean
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
        self.externalProvider = externalProvider
        self.externalCalendarId = externalCalendarId
        self.externalETag = externalETag
        self.pendingCreateRemoteId = pendingCreateRemoteId
        self.localUpdatedAt = localUpdatedAt
        self.remoteUpdatedAt = remoteUpdatedAt
        self.syncState = syncState
    }
}

extension CalendarEvent {
    /// Даты в разумных пределах (1970…2200). Всё остальное — не дата, а
    /// отсутствие даты, закодированное как `0000-00-00` или `distantPast`.
    var hasPlausibleDates: Bool {
        let range = LegalicTaskMapper.plausibleDateRange
        return range.contains(startDate) && range.contains(endDate)
    }
}

enum EventSyncState: String, Codable, Sendable {
    case clean
    case pendingUpload
}

struct PendingEventDeletion: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let remoteRef: RemoteEventRef
    let queuedAt: Date
    var etag: String?

    init(id: UUID = UUID(), remoteRef: RemoteEventRef, queuedAt: Date = Date(), etag: String? = nil) {
        self.id = id
        self.remoteRef = remoteRef
        self.queuedAt = queuedAt
        self.etag = etag
    }
}

enum EventColor: String, Codable, CaseIterable, Sendable {
    case red = "red"
    case orange = "orange"
    case yellow = "yellow"
    case green = "green"
    case blue = "blue"
    case purple = "purple"
    case pink = "pink"
    case brown = "brown"
    case gray = "gray"

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
        case .gray: return Color(red: 0.65, green: 0.67, blue: 0.7)
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
        case .gray: return "Серый"
        }
    }

    static func nearest(to hex: String?, fallback: EventColor) -> EventColor {
        guard let hex else { return fallback }
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return fallback }
        let rgb = (
            Double((value >> 16) & 0xff) / 255,
            Double((value >> 8) & 0xff) / 255,
            Double(value & 0xff) / 255
        )
        let palette: [(EventColor, (Double, Double, Double))] = [
            (.red, (0.95, 0.6, 0.6)), (.orange, (0.95, 0.75, 0.5)),
            (.yellow, (0.95, 0.9, 0.6)), (.green, (0.7, 0.9, 0.7)),
            (.blue, (0.6, 0.8, 0.95)), (.purple, (0.8, 0.7, 0.95)),
            (.pink, (0.95, 0.7, 0.85)), (.brown, (0.8, 0.7, 0.6)),
            (.gray, (0.65, 0.67, 0.7)),
        ]
        return palette.min { lhs, rhs in
            distance(rgb, lhs.1) < distance(rgb, rhs.1)
        }?.0 ?? fallback
    }

    private static func distance(
        _ lhs: (Double, Double, Double),
        _ rhs: (Double, Double, Double)
    ) -> Double {
        let dr = lhs.0 - rhs.0
        let dg = lhs.1 - rhs.1
        let db = lhs.2 - rhs.2
        return dr * dr + dg * dg + db * db
    }
}

enum ViewMode: String, CaseIterable {
    case day = "День"
    case week = "Неделя"
    case month = "Месяц"
    case year = "Год"
}
