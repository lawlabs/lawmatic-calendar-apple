//
//  EventInspectorView.swift
//  CalendarTest45
//
//  Created by Sergey on 06.02.2026.
//

import SwiftUI

/// Inspector панель для просмотра и редактирования события (как в Apple Calendar)
struct EventInspectorView: View {
    @ObservedObject var viewModel: CalendarViewModel

    private enum FocusField {
        case title
        case location
        case notes
    }

    // Состояния редактирования
    @State private var title: String = ""
    @State private var location: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date().addingTimeInterval(3600)
    @State private var isAllDay: Bool = false
    @State private var notes: String = ""
    @State private var selectedCalendarId: UUID = UUID()
    @FocusState private var focusedField: FocusField?
    @State private var isApplyingModelState = false

    private var inspectedEvent: CalendarEvent? {
        viewModel.selectedEvent
    }

    private var isCreatingNewEvent: Bool {
        if case .create = viewModel.inspectorState {
            return true
        }

        return false
    }

    private var isReadOnly: Bool {
        guard let event = inspectedEvent else { return false }
        return !viewModel.canEdit(event)
    }

    var body: some View {
        VStack(spacing: 0) {
            InspectorMiniCalendar(viewModel: viewModel)

            Divider()

            if inspectedEvent != nil {
                editorView
            } else {
                emptyStateView
            }
        }
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
        .onChange(of: viewModel.inspectorState) { _, _ in
            DispatchQueue.main.async {
                loadEventData()
                updateFocus()
            }
        }
        .onChange(of: inspectedEvent?.startDate) { _, _ in
            syncDraftTimingIfNeeded()
        }
        .onChange(of: inspectedEvent?.endDate) { _, _ in
            syncDraftTimingIfNeeded()
        }
        .onAppear {
            DispatchQueue.main.async {
                loadEventData()
                updateFocus()
            }
        }
        .onChange(of: title) { _, _ in
            persistChangesIfNeeded()
        }
        .onChange(of: location) { _, _ in
            persistChangesIfNeeded()
        }
        .onChange(of: startDate) { _, _ in
            persistChangesIfNeeded()
        }
        .onChange(of: endDate) { _, _ in
            persistChangesIfNeeded()
        }
        .onChange(of: isAllDay) { _, _ in
            persistChangesIfNeeded()
        }
        .onChange(of: notes) { _, _ in
            persistChangesIfNeeded()
        }
        .onChange(of: selectedCalendarId) { _, _ in
            persistChangesIfNeeded()
        }
    }

    private var editorView: some View {
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

                TextField("Название", text: $title)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focusedField, equals: .title)

                TextField("Место или видеозвонок", text: $location)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .location)
            }

            Section {
                Toggle("Весь день", isOn: $isAllDay)

                DatePicker(
                    "Начало",
                    selection: $startDate,
                    displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                )

                DatePicker(
                    "Конец",
                    selection: $endDate,
                    displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                )
            }

            Section("Календарь") {
                Picker("Календарь", selection: $selectedCalendarId) {
                    ForEach(viewModel.calendars.filter { $0.isWritable || $0.id == selectedCalendarId }) { calendar in
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
                TextEditor(text: $notes)
                    .frame(minHeight: 120)
                    .focused($focusedField, equals: .notes)
            }

            if let event = inspectedEvent {
                Section {
                    Button(role: .destructive) {
                        viewModel.deleteEvent(event)
                    } label: {
                        HStack {
                            Spacer()
                            Text("Удалить событие")
                            Spacer()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .disabled(isReadOnly)
    }

    // MARK: - Empty State (событие не выбрано)

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Событие не выбрано")
                .font(.title3)
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func loadEventData() {
        isApplyingModelState = true
        let event = inspectedEvent

        if let event = event {
            title = event.title
            location = event.location
            startDate = event.startDate
            endDate = event.endDate
            isAllDay = event.isAllDay
            notes = event.notes
            selectedCalendarId = event.calendarId
        } else {
            let defaultDates = viewModel.defaultDatesForNewEvent()
            title = ""
            location = ""
            startDate = defaultDates.start
            endDate = defaultDates.end
            isAllDay = false
            notes = ""
            selectedCalendarId = viewModel.defaultCalendarId
        }

        DispatchQueue.main.async {
            isApplyingModelState = false
        }
    }

    private func updateFocus() {
        guard focusedField == nil, isCreatingNewEvent, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        focusedField = .title
    }

    private func syncDraftTimingIfNeeded() {
        guard isCreatingNewEvent, let event = inspectedEvent else { return }
        isApplyingModelState = true
        startDate = event.startDate
        endDate = event.endDate
        isAllDay = event.isAllDay
        selectedCalendarId = event.calendarId
        DispatchQueue.main.async {
            isApplyingModelState = false
        }
    }

    private var selectedCalendar: CalendarItem? {
        viewModel.calendars.first { $0.id == selectedCalendarId }
    }

    private func persistChangesIfNeeded() {
        guard !isApplyingModelState, let existingEvent = inspectedEvent else {
            return
        }
        guard viewModel.canEdit(existingEvent) else { return }

        let minimumDuration: TimeInterval = isAllDay ? 0 : 15 * 60
        let normalizedEndDate = max(endDate, startDate.addingTimeInterval(minimumDuration))
        if normalizedEndDate != endDate {
            endDate = normalizedEndDate
            return
        }

        var updatedEvent = existingEvent
        updatedEvent.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedEvent.startDate = startDate
        updatedEvent.endDate = normalizedEndDate
        updatedEvent.isAllDay = isAllDay
        updatedEvent.notes = notes
        updatedEvent.location = location
        updatedEvent.calendarId = selectedCalendarId

        guard updatedEvent != existingEvent else {
            return
        }

        viewModel.applyInspectorChanges(updatedEvent)
    }
}

// MARK: - Обёртка для календарика в инспекторе с навигацией

struct InspectorMiniCalendar: View {
    @ObservedObject var viewModel: CalendarViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            MiniCalendarView(viewModel: viewModel)
                .layoutPriority(1)


                HStack(alignment: .top, spacing: 6) {
                    Button {
                        viewModel.moveToPreviousPeriod()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)

                    Button("Сегодня") {
                        viewModel.moveToToday()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        viewModel.moveToNextPeriod()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                }
                .fixedSize()

        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }
}
