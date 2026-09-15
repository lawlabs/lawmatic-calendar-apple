//
//  EventInspectorView.swift
//  CalendarTest45
//
//  Created by Sergey on 06.02.2026.
//

import SwiftUI

/// Inspector панель для просмотра и редактирования события (как в Apple Calendar).
struct EventInspectorView: View {
    var viewModel: CalendarViewModel

    var body: some View {
        Group {
            if let event = viewModel.selectedEvent, let state = viewModel.inspectorState {
                EventEditorForm(
                    event: event,
                    isCreating: {
                        if case .create = state { return true }
                        return false
                    }(),
                    isReadOnly: !viewModel.canEdit(event),
                    calendars: viewModel.calendars,
                    onChange: { viewModel.applyInspectorChanges($0) },
                    onDelete: { viewModel.deleteEvent(event) }
                )
                // Новая идентичность на каждое событие: @State формы
                // создаётся заново, без ручной «перезагрузки» полей.
                .id(event.id)
            } else {
                emptyStateView
            }
        }
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)

            Text("Событие не выбрано")
                .font(.title3)
                .foregroundColor(.secondary)

            Text("Выберите событие или создайте новое двойным щелчком по сетке.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Редактируемые поля события. Отдельная структура, чтобы один `onChange`
/// обрабатывал все правки, а сравнение с событием было тривиальным.
private struct EventDraft: Equatable {
    var title: String
    var location: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var notes: String
    var calendarId: UUID

    init(_ event: CalendarEvent) {
        title = event.title
        location = event.location
        startDate = event.startDate
        endDate = event.endDate
        isAllDay = event.isAllDay
        notes = event.notes
        calendarId = event.calendarId
    }

    func applied(to event: CalendarEvent) -> CalendarEvent {
        var updated = event
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.location = location
        updated.startDate = startDate
        updated.endDate = endDate
        updated.isAllDay = isAllDay
        updated.notes = notes
        updated.calendarId = calendarId
        return updated
    }
}

private struct EventEditorForm: View {
    let event: CalendarEvent
    let isCreating: Bool
    let isReadOnly: Bool
    let calendars: [CalendarItem]
    let onChange: (CalendarEvent) -> Void
    let onDelete: () -> Void

    private enum FocusField {
        case title
        case location
        case notes
    }

    @State private var draft: EventDraft
    /// Последняя версия, которую форма отправила во VM. Нужна, чтобы отличить
    /// «эхо» собственной правки от внешнего изменения (drag, синк).
    @State private var lastPushedEvent: CalendarEvent
    @FocusState private var focusedField: FocusField?

    init(
        event: CalendarEvent,
        isCreating: Bool,
        isReadOnly: Bool,
        calendars: [CalendarItem],
        onChange: @escaping (CalendarEvent) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.event = event
        self.isCreating = isCreating
        self.isReadOnly = isReadOnly
        self.calendars = calendars
        self.onChange = onChange
        self.onDelete = onDelete
        _draft = State(initialValue: EventDraft(event))
        _lastPushedEvent = State(initialValue: event)
    }

    private var selectedCalendar: CalendarItem? {
        calendars.first { $0.id == draft.calendarId }
    }

    private var selectableCalendars: [CalendarItem] {
        calendars.filter { $0.isWritable || $0.id == draft.calendarId }
    }

    var body: some View {
        Form {
            if isReadOnly {
                Section {
                    Label("Этот календарь доступен только для чтения", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if let selectedCalendar {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(selectedCalendar.color.color)
                            .frame(width: 10, height: 10)

                        Text(selectedCalendar.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                TextField("Название", text: $draft.title)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focusedField, equals: .title)
                    .accessibilityLabel("Название события")

                TextField("Место или видеозвонок", text: $draft.location)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .location)
                    .accessibilityLabel("Место")
            }

            Section {
                Toggle("Весь день", isOn: $draft.isAllDay)

                DatePicker(
                    "Начало",
                    selection: $draft.startDate,
                    displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute]
                )

                DatePicker(
                    "Конец",
                    selection: $draft.endDate,
                    displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute]
                )
            }

            Section("Календарь") {
                Picker("Календарь", selection: $draft.calendarId) {
                    ForEach(selectableCalendars) { calendar in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(calendar.color.color)
                                .frame(width: 12, height: 12)
                            Text(calendar.name)
                        }
                        .tag(calendar.id)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Заметки") {
                TextEditor(text: $draft.notes)
                    .frame(minHeight: 120)
                    .focused($focusedField, equals: .notes)
                    .accessibilityLabel("Заметки")
            }

            Section {
                Button(role: .destructive, action: onDelete) {
                    HStack {
                        Spacer()
                        Text("Удалить событие")
                        Spacer()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .disabled(isReadOnly)
        .onAppear {
            if isCreating, draft.title.isEmpty {
                focusedField = .title
            }
        }
        .onChange(of: draft) { _, _ in
            pushDraftIfNeeded()
        }
        .onChange(of: event) { _, newEvent in
            // Внешнее изменение (перетаскивание, растяжение черновика,
            // синхронизация) — перечитать поля. Собственное эхо пропускаем.
            // Сравниваем только редактируемые поля: VM дописывает служебные
            // (localUpdatedAt, syncState), и это не повод перечитывать форму.
            guard EventDraft(newEvent) != EventDraft(lastPushedEvent) else { return }
            lastPushedEvent = newEvent
            draft = EventDraft(newEvent)
        }
    }

    private func pushDraftIfNeeded() {
        guard !isReadOnly else { return }

        let minimumDuration: TimeInterval = draft.isAllDay ? 0 : 15 * 60
        let normalizedEndDate = max(draft.endDate, draft.startDate.addingTimeInterval(minimumDuration))
        if normalizedEndDate != draft.endDate {
            draft.endDate = normalizedEndDate
            return
        }

        let updated = draft.applied(to: event)
        guard updated != event else { return }

        lastPushedEvent = updated
        onChange(updated)
    }
}
