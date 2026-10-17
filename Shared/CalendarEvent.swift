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
    /// Запись нельзя менять из приложения независимо от прав календаря
    /// (например, экземпляр повторяющегося события Apple Calendar).
    var isReadOnly: Bool

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
        syncState: EventSyncState = .clean,
        isReadOnly: Bool = false
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
        self.isReadOnly = isReadOnly
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, startDate, endDate, isAllDay, notes, location, calendarId
        case externalId, externalProvider, externalCalendarId, externalETag, pendingCreateRemoteId
        case localUpdatedAt, remoteUpdatedAt, syncState, isReadOnly
    }

    /// Ручное декодирование ради обратной совместимости файлов: новые
    /// необязательные поля читаются через `decodeIfPresent`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        isAllDay = try container.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? false
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
        calendarId = try container.decode(UUID.self, forKey: .calendarId)
        externalId = try container.decodeIfPresent(String.self, forKey: .externalId)
        externalProvider = try container.decodeIfPresent(ProviderID.self, forKey: .externalProvider)
        externalCalendarId = try container.decodeIfPresent(String.self, forKey: .externalCalendarId)
        externalETag = try container.decodeIfPresent(String.self, forKey: .externalETag)
        pendingCreateRemoteId = try container.decodeIfPresent(String.self, forKey: .pendingCreateRemoteId)
        localUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .localUpdatedAt) ?? Date()
        remoteUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .remoteUpdatedAt)
        syncState = try container.decodeIfPresent(EventSyncState.self, forKey: .syncState) ?? .clean
        isReadOnly = try container.decodeIfPresent(Bool.self, forKey: .isReadOnly) ?? false
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

    /// Цвет палитры для цвета календаря провайдера (`#RRGGBB`).
    ///
    /// Палитра пастельная, а календари Apple и Google насыщенные, поэтому
    /// сравнивается оттенок, а не расстояние в RGB: по RGB насыщенный
    /// фиолетовый ближе к серому, а зелёный — к коричневому. Почти
    /// бесцветный — серый, тёмный оранжевый — коричневый.
    static func nearest(to hex: String?, fallback: EventColor) -> EventColor {
        guard let hex else { return fallback }
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return fallback }
        let red = Double((value >> 16) & 0xff) / 255
        let green = Double((value >> 8) & 0xff) / 255
        let blue = Double(value & 0xff) / 255

        let maximum = max(red, green, blue)
        let chroma = maximum - min(red, green, blue)
        let saturation = maximum > 0 ? chroma / maximum : 0
        guard saturation >= 0.15, maximum >= 0.15 else { return .gray }

        var hue: Double
        switch maximum {
        case red: hue = 60 * ((green - blue) / chroma)
        case green: hue = 60 * ((blue - red) / chroma + 2)
        default: hue = 60 * ((red - green) / chroma + 4)
        }
        if hue < 0 { hue += 360 }

        if (12 ..< 50).contains(hue), maximum < 0.7 { return .brown }
        switch hue {
        case 12 ..< 45: return .orange
        case 45 ..< 70: return .yellow
        case 70 ..< 170: return .green
        case 170 ..< 250: return .blue
        case 250 ..< 300: return .purple
        case 300 ..< 335: return .pink
        default: return .red
        }
    }
}

enum ViewMode: String, CaseIterable {
    case day = "День"
    case week = "Неделя"
    case month = "Месяц"
    case year = "Год"
}
