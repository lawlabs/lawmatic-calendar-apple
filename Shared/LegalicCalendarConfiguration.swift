import Foundation

enum LegalicCalendarConfiguration {
    static let sourceTag = "legalic"
    static let displayName = "LEGALIC"
    private static let uuidKey = "legalic.calendarItemUUID"

    static var stableCalendarId: UUID {
        if let rawValue = UserDefaults.standard.string(forKey: uuidKey),
           let uuid = UUID(uuidString: rawValue) {
            return uuid
        }

        let uuid = UUID()
        UserDefaults.standard.set(uuid.uuidString, forKey: uuidKey)
        return uuid
    }
}
