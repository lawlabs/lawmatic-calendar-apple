import SwiftUI

struct LegalicSettingsPane: View {
    @ObservedObject var provider: LegalicProvider
    @State private var connectionError: String?

    var body: some View {
        Form {
            Section("LEGALIC") {
                Toggle("Синхронизировать задачи", isOn: $provider.isEnabled)
                    .disabled(!provider.hasCredentials)
                Label("Интеграция доступна только для чтения: API записи задач в проекте не описан.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Ключи API") {
                TextField("API Key", text: $provider.apiKey)
                    .textFieldStyle(.roundedBorder)
                SecureField("API Secret", text: $provider.apiSecret)
                    .textFieldStyle(.roundedBorder)
                Text("API Key и API Secret хранятся в Keychain, а не в UserDefaults.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                connectionControls
            }

            Section("Сервер") {
                TextField("Базовый URL", text: $provider.apiBaseURL)
                    .textFieldStyle(.roundedBorder)
                TextField("Путь к списку задач", text: $provider.tasksListPath)
                    .textFieldStyle(.roundedBorder)

                Toggle("Запрашивать видимый период", isOn: $provider.syncTasksInVisibleRangeOnly)
                HStack {
                    TextField("Параметр from", text: $provider.tasksQueryParamFrom)
                    TextField("Параметр to", text: $provider.tasksQueryParamTo)
                }
                Stepper("Страниц за синк: \(provider.taskSyncMaxPages)", value: $provider.taskSyncMaxPages, in: 1 ... 100)
                Stepper("Задач на страницу: \(provider.taskSyncPerPage)", value: $provider.taskSyncPerPage, in: 10 ... 500, step: 10)
                Text("LEGALIC может вернуть только первые N страниц. Поэтому клиент делает точечный upsert и не считает отсутствующую задачу удалённой.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let connectionError {
                Section { Text(connectionError).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var connectionControls: some View {
        HStack {
            Text(provider.status.shortDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if provider.status.isSignedIn {
                Button("Отключить") { Task { await provider.signOut() } }
            } else {
                Button("Проверить и подключить") {
                    Task {
                        do { try await provider.signIn(); connectionError = nil }
                        catch { connectionError = error.localizedDescription }
                    }
                }
                .disabled(!provider.hasCredentials)
            }
        }
    }
}
