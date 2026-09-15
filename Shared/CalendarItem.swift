import SwiftUI

struct CalendarItem: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var color: EventColor
    var isVisible: Bool = true
    var accountName: String
    var externalProvider: ProviderID?
    var externalId: String?
    var isWritable: Bool
    var syncToken: String?
    /// Конец окна первичной выборки (для провайдеров с ограниченным full-sync).
    /// Когда окно почти закончилось, `syncToken` сбрасывается и делается новая
    /// полная выборка с новым окном.
    var syncWindowEnd: Date?

    init(
        id: UUID = UUID(),
        name: String,
        color: EventColor,
        isVisible: Bool = true,
        accountName: String = "Локально",
        externalProvider: ProviderID? = nil,
        externalId: String? = nil,
        isWritable: Bool = true,
        syncToken: String? = nil,
        syncWindowEnd: Date? = nil
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
        self.syncWindowEnd = syncWindowEnd
    }
}
