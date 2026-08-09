import SwiftUI

struct CalendarItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var color: EventColor
    var isVisible: Bool = true
    var accountName: String
    var externalProvider: ProviderID?
    var externalId: String?
    var isWritable: Bool
    var syncToken: String?

    init(
        id: UUID = UUID(),
        name: String,
        color: EventColor,
        isVisible: Bool = true,
        accountName: String = "Локально",
        externalProvider: ProviderID? = nil,
        externalId: String? = nil,
        isWritable: Bool = true,
        syncToken: String? = nil
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.isVisible = isVisible
        self.accountName = accountName
        self.externalProvider = externalProvider
        self.externalId = externalId
        self.isWritable = isWritable
        self.syncToken = syncToken
    }
}
