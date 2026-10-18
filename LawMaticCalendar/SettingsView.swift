import SwiftUI

/// Настройки приложения: на Mac — окно настроек со вкладками на панели
/// инструментов, на iPhone и iPad — форма в листе.
///
/// Аккаунты создают настоящие провайдеры, а LEGALIC при этом читает пароль
/// из Keychain, поэтому в демо-режиме и при запуске для тестов вместо них
/// показывается заглушка.
struct SettingsView: View {
    let display: CalendarDisplaySettings

    var body: some View {
        #if os(macOS)
        TabView {
            Tab("Основные", systemImage: "gearshape") {
                Form {
                    CalendarDisplaySettingsSections(display: display)
                }
                .formStyle(.grouped)
                .settingsTabFrame()
            }

            if DemoMode.usesUserAccounts {
                Tab(ProviderID.google.displayName, systemImage: ProviderID.google.systemImageName) {
                    GoogleSettingsPane(provider: ProviderRegistry.shared.google)
                        .settingsTabFrame()
                }
                Tab(ProviderID.apple.displayName, systemImage: ProviderID.apple.systemImageName) {
                    AppleSettingsPane(provider: ProviderRegistry.shared.apple)
                        .settingsTabFrame()
                }
                Tab(ProviderID.legalic.displayName, systemImage: ProviderID.legalic.systemImageName) {
                    LegalicSettingsPane(provider: ProviderRegistry.shared.legalic)
                        .settingsTabFrame()
                }
            } else {
                Tab("Аккаунты", systemImage: "person.crop.circle") {
                    AccountsUnavailableView()
                }
            }
        }
        #else
        Form {
            CalendarDisplaySettingsSections(display: display)

            if DemoMode.usesUserAccounts {
                AccountsSection()
            } else {
                Section("Аккаунты") {
                    Text("В демо-режиме аккаунты не подключаются.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        #endif
    }
}

#if os(macOS)
private extension View {
    /// Вкладка окна настроек: постоянная ширина, высота по содержимому.
    func settingsTabFrame() -> some View {
        frame(width: 620)
            .fixedSize(horizontal: false, vertical: true)
    }
}
#else
/// Аккаунты в настройках iPhone и iPad: строка со статусом ведёт к
/// настройкам провайдера.
private struct AccountsSection: View {
    @ObservedObject private var google = ProviderRegistry.shared.google
    @ObservedObject private var apple = ProviderRegistry.shared.apple
    @ObservedObject private var legalic = ProviderRegistry.shared.legalic

    var body: some View {
        Section("Аккаунты") {
            NavigationLink {
                GoogleSettingsPane(provider: google)
                    .navigationTitle(ProviderID.google.displayName)
            } label: {
                AccountRow(id: .google, status: google.status, isEnabled: google.isEnabled)
            }
            NavigationLink {
                AppleSettingsPane(provider: apple)
                    .navigationTitle(ProviderID.apple.displayName)
            } label: {
                AccountRow(id: .apple, status: apple.status, isEnabled: apple.isEnabled)
            }
            NavigationLink {
                LegalicSettingsPane(provider: legalic)
                    .navigationTitle(ProviderID.legalic.displayName)
            } label: {
                AccountRow(id: .legalic, status: legalic.status, isEnabled: legalic.isEnabled)
            }
        }
    }
}

/// Название аккаунта, его статус и значок, выделенный цветом, когда
/// синхронизация включена.
private struct AccountRow: View {
    let id: ProviderID
    let status: ProviderStatus
    let isEnabled: Bool

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(id.displayName)
                Text(status.shortDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: id.systemImageName)
                .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
        }
    }
}
#endif

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
