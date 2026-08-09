import Combine
import Foundation

@MainActor
final class ProviderRegistry: ObservableObject {
    static let shared = ProviderRegistry()

    @Published private(set) var registeredIDs: [ProviderID] = []
    private var providers: [ProviderID: any CalendarProvider] = [:]

    private init() {
        register(LegalicProvider())
        register(AppleCalendarProvider())
        register(GoogleCalendarProvider())
    }

    func register(_ provider: any CalendarProvider) {
        providers[provider.id] = provider
        registeredIDs = ProviderID.allCases.filter { providers[$0] != nil }
    }

    func provider(_ id: ProviderID) -> (any CalendarProvider)? {
        providers[id]
    }

    var enabledProviders: [any CalendarProvider] {
        ProviderID.allCases.compactMap { providers[$0] }.filter(\.isEnabled)
    }

    var legalic: LegalicProvider {
        typed(.legalic, as: LegalicProvider.self)
    }

    var google: GoogleCalendarProvider {
        typed(.google, as: GoogleCalendarProvider.self)
    }

    var apple: AppleCalendarProvider {
        typed(.apple, as: AppleCalendarProvider.self)
    }

    private func typed<T>(_ id: ProviderID, as type: T.Type) -> T {
        guard let provider = providers[id] as? T else {
            preconditionFailure("Провайдер \(id.rawValue) не зарегистрирован.")
        }
        return provider
    }
}
