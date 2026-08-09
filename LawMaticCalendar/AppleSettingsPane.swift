import SwiftUI

struct AppleSettingsPane: View {
    @ObservedObject var provider: AppleCalendarProvider
    @State private var connectionError: String?

    var body: some View {
        Form {
            Section("Apple Calendar") {
                Toggle("Синхронизировать системные календари", isOn: $provider.isEnabled)
                    .disabled(!provider.status.isSignedIn)
                Text("EventKit даёт доступ к локальным и iCloud-календарям, подключённым в системе.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Доступ") {
                HStack {
                    Text(provider.status.shortDescription)
                    Spacer()
                    if provider.status.isSignedIn {
                        Button("Выключить") { Task { await provider.signOut() } }
                    } else {
                        Button("Разрешить полный доступ") {
                            Task {
                                do { try await provider.signIn(); connectionError = nil }
                                catch { connectionError = error.localizedDescription }
                            }
                        }
                    }
                }
                Text("Отозвать системное разрешение можно в Настройках системы → Конфиденциальность и безопасность → Календари.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let connectionError {
                    Text(connectionError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }
}
