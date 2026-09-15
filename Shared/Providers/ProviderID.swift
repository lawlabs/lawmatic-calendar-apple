import Foundation

/// Идентификатор внешнего провайдера календаря.
///
/// Используется в `CalendarEvent.externalProvider` для пометки события,
/// пришедшего из конкретного провайдера, и как ключ в `ProviderRegistry`.
enum ProviderID: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case legalic
    case google
    case apple
    // case microsoft — позже

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .legalic: return "LEGALIC"
        case .google:  return "Google Calendar"
        case .apple:   return "Apple Calendar"
        }
    }

    var systemImageName: String {
        switch self {
        case .legalic: return "building.2"
        case .google:  return "globe"
        case .apple:   return "applelogo"
        }
    }

    var defaultColor: EventColor {
        switch self {
        case .legalic: return .purple
        case .google:  return .blue
        case .apple:   return .gray
        }
    }
}
