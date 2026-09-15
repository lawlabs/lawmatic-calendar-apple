import SwiftUI

struct LegalicSettingsPane: View {
    @ObservedObject var provider: LegalicProvider
    @State private var connectionError: String?
    @State private var isSigningIn = false

    private var isSignedIn: Bool { provider.status.isSignedIn }

    var body: some View {
        Form {
            Section("LEGALIC") {
                Toggle("Синхронизировать задачи и сроки", isOn: $provider.isEnabled)
                    .disabled(!isSignedIn)
                Text("Задачи и сроки по делам читаются лентой /sync/v1 по учётной записи LEGALIC. Первый обмен читает всю ленту, дальше — только изменения.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Показывать задачи за", selection: $provider.historyHorizonMonths) {
                    ForEach(LegalicProvider.historyHorizonOptions, id: \.self) { months in
                        Text(LegalicProvider.historyHorizonTitle(months: months)).tag(months)
                    }
                }
                .disabled(!isSignedIn)
                Text("Лента LEGALIC не фильтруется по датам: читается вся, а в календарь попадают только задачи и сроки не старше выбранного периода. Смена периода перечитывает ленту.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(provider.requiresFullResync
                         ? "При следующей синхронизации лента будет прочитана с начала."
                         : "Если данные разошлись с сервером, ленту можно перечитать с начала.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Перечитать заново") { provider.requestFullResync() }
                        .disabled(!isSignedIn || provider.requiresFullResync)
                }
            }

            Section("Учётная запись") {
                TextField("Сервер", text: $provider.server, prompt: Text(LegalicProvider.defaultServer))
                    .textFieldStyle(.roundedBorder)
                    .disabled(isSignedIn)
                    .accessibilityLabel("Сервер LEGALIC")
                TextField("Почта", text: $provider.login)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isSignedIn)
                    .textContentType(.username)
                    .accessibilityLabel("Почта учётной записи")
                SecureField("Пароль", text: $provider.password)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isSignedIn)
                    .textContentType(.password)
                    .onSubmit { signInIfPossible() }
                    .accessibilityLabel("Пароль")
                Text("Пароль попадает в Связку ключей только после того, как сервер подтвердил вход. В настройках приложения он не хранится.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                connectionControls
            }

            Section("Запись") {
                Toggle("Разрешить изменять задачи из календаря", isOn: $provider.allowsWriteBack)
                    .disabled(!isSignedIn)
                Text("Когда включено, создание, перенос и удаление событий в календаре «LEGALIC · Задачи» уходят на сервер (POST /sync/v1/task с проверкой версии). Сроки по делам — только для чтения.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let connectionError {
                Section { Text(connectionError).foregroundStyle(.red).textSelection(.enabled) }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var connectionControls: some View {
        HStack {
            if isSigningIn {
                ProgressView().controlSize(.small)
                Text("Проверяем вход…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(provider.status.shortDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if isSignedIn {
                Button("Выйти") {
                    Task {
                        await provider.signOut()
                        connectionError = nil
                    }
                }
            } else {
                Button("Войти") { signInIfPossible() }
                    .disabled(!provider.canSignIn || isSigningIn)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func signInIfPossible() {
        guard provider.canSignIn, !isSigningIn else { return }
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            do {
                try await provider.signIn()
                connectionError = nil
            } catch {
                connectionError = error.localizedDescription
            }
        }
    }
}
