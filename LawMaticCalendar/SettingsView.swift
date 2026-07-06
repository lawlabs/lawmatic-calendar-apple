//
//  SettingsView.swift
//  LawMaticCalendar
//
//  Окно настроек: доступ к LEGALIC (ключи API и режим данных).
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var legalicService = LegalicService.shared

    var body: some View {
        Form {
            Section {
                Text("Введите ключи API LEGALIC для загрузки данных календаря и справочников.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Сервер") {
                TextField("Базовый URL", text: $legalicService.apiBaseURL)
                    .textFieldStyle(.roundedBorder)
                Text("Обычно https://legalic.ru — без слэша в конце.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                TextField("Путь к списку задач", text: $legalicService.tasksListPath)
                    .textFieldStyle(.roundedBorder)
                Text("По умолчанию api/v1/task (единственное число). Путь …/tasks на сервере отсутствует.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Toggle("Только видимый период календаря", isOn: $legalicService.syncTasksInVisibleRangeOnly)
                Text("Вкл.: к URL добавляются «с — по» (на стороне LEGALIC фильтр может не применяться). Выкл.: только пагинация без from/to.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Stepper(value: $legalicService.taskSyncMaxPages, in: 1 ... 100) {
                    Text("Страниц за синк: \(legalicService.taskSyncMaxPages)")
                }
                Text("Подряд запрашиваются page=1…min(page_count, это число). Для теста хватит нескольких страниц; полная база — сотни запросов.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Stepper(value: $legalicService.taskSyncPerPage, in: 10 ... 200, step: 10) {
                    Text("Задач на страницу (per_page): \(legalicService.taskSyncPerPage)")
                }
                Text("Ограничение в клиенте — до 500; сервер может отдавать меньше.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline) {
                    Text("Параметр «с»")
                        .frame(width: 100, alignment: .leading)
                    TextField("from", text: $legalicService.tasksQueryParamFrom)
                        .textFieldStyle(.roundedBorder)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Параметр «по»")
                        .frame(width: 100, alignment: .leading)
                    TextField("to", text: $legalicService.tasksQueryParamTo)
                        .textFieldStyle(.roundedBorder)
                }
                Text("Имена должны совпадать с фильтром API на сервере (при необходимости смотрите LawMatic B2 / документацию LEGALIC).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("Ключи API") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("API Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("API Key", text: $legalicService.apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("API Secret")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("API Secret", text: $legalicService.apiSecret)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 8) {
                    Image(systemName: legalicService.hasCredentials ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(legalicService.hasCredentials ? .green : .orange)
                    Text(legalicService.hasCredentials ? "Ключи заданы" : "Укажите API Key и API Secret")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Режим работы с данными") {
                Picker("Режим", selection: $legalicService.dataMode) {
                    ForEach(LegalicDataMode.allCases) { mode in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.rawValue)
                            Text(mode.description)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .tag(mode)
                    }
                }
                #if os(macOS)
                .pickerStyle(.radioGroup)
                #else
                .pickerStyle(.menu)
                #endif

                if legalicService.dataMode == .hybrid {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text("В гибридном режиме можно сочетать локальный кэш и LEGALIC; при выборе элемента из LEGALIC он может быть импортирован локально.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 420)
        .padding()
    }
}

#if DEBUG
#Preview {
    SettingsView()
}
#endif
