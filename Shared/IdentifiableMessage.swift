import Foundation

struct IdentifiableMessage: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}
