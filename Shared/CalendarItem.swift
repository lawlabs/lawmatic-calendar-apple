import SwiftUI

struct CalendarItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var color: EventColor
    var isVisible: Bool = true
    var accountName: String

    init(
        id: UUID = UUID(),
        name: String,
        color: EventColor,
        isVisible: Bool = true,
        accountName: String = "Локально"
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.isVisible = isVisible
        self.accountName = accountName
    }
}
