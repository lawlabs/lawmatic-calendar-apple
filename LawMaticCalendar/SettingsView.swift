import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case google
    case apple
    case legalic

    var id: String { rawValue }

    var providerID: ProviderID {
        switch self {
        case .google: return .google
        case .apple: return .apple
        case .legalic: return .legalic
        }
    }
}

struct SettingsView: View {
    @State private var selection: SettingsSection? = .google
    @ObservedObject private var google = ProviderRegistry.shared.google
    @ObservedObject private var apple = ProviderRegistry.shared.apple
    @ObservedObject private var legalic = ProviderRegistry.shared.legalic

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Аккаунты календарей") {
                    ForEach(SettingsSection.allCases) { section in
                        NavigationLink(value: section) {
                            providerRow(for: section)
                        }
                    }
                }
            }
            .navigationTitle("Настройки")
            .frame(minWidth: 220)
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
        }
        #if os(macOS)
        .frame(minWidth: 760, minHeight: 460)
        #endif
    }

    @ViewBuilder
    private func providerRow(for section: SettingsSection) -> some View {
        let status = status(for: section)
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.providerID.displayName)
                Text(status.shortDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: section.providerID.systemImageName)
                .foregroundStyle(isEnabled(section) ? Color.accentColor : Color.secondary)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection ?? .google {
        case .google:
            GoogleSettingsPane(provider: google)
        case .apple:
            AppleSettingsPane(provider: apple)
        case .legalic:
            LegalicSettingsPane(provider: legalic)
        }
    }

    private func status(for section: SettingsSection) -> ProviderStatus {
        switch section {
        case .google: return google.status
        case .apple: return apple.status
        case .legalic: return legalic.status
        }
    }

    private func isEnabled(_ section: SettingsSection) -> Bool {
        switch section {
        case .google: return google.isEnabled
        case .apple: return apple.isEnabled
        case .legalic: return legalic.isEnabled
        }
    }
}

extension ProviderStatus {
    var shortDescription: String {
        switch self {
        case .signedOut: return "не подключено"
        case .syncing: return "подключение…"
        case .signedIn(let label): return label
        case .error(let message): return "ошибка: \(message.prefix(50))"
        }
    }

    var isSignedIn: Bool {
        if case .signedIn = self { return true }
        return false
    }
}
