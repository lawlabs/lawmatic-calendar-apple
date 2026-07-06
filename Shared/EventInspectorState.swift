import Foundation

enum EventInspectorState: Equatable, Identifiable {
    case create(eventID: UUID)
    case view(eventID: UUID)
    case edit(eventID: UUID)

    var eventID: UUID? {
        switch self {
        case .create(let eventID), .view(let eventID), .edit(let eventID):
            return eventID
        }
    }

    var isEditing: Bool {
        switch self {
        case .create, .edit:
            return true
        case .view:
            return false
        }
    }

    var id: String {
        switch self {
        case .create(let eventID):
            return "create-\(eventID.uuidString)"
        case .view(let eventID):
            return "view-\(eventID.uuidString)"
        case .edit(let eventID):
            return "edit-\(eventID.uuidString)"
        }
    }
}
