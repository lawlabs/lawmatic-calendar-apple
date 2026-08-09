import SwiftUI

struct GoogleSettingsPane: View {
    @ObservedObject var provider: GoogleCalendarProvider
    @State private var connectionError: String?

    var body: some View {
        Form {
            Section("Google Calendar") {
                Toggle("Синхронизировать календари", isOn: $provider.isEnabled)
                    .disabled(!provider.status.isSignedIn)
                Text("События читаются и записываются через Google Calendar API. Изменения загружаются инкрементально по syncToken.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Аккаунт") {
                HStack {
                    Text(provider.status.shortDescription)
                    Spacer()
                    if provider.status.isSignedIn {
                        Button("Выйти") { Task { await provider.signOut() } }
                    } else {
                        Button("Войти с Google") {
                            Task {
                                do { try await provider.signIn(); connectionError = nil }
                                catch { connectionError = error.localizedDescription }
                            }
                        }
                        .disabled(!provider.isConfigured)
                    }
                }
                if let message = provider.configurationMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let connectionError {
                    Text(connectionError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }
}
