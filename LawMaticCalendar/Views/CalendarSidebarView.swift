import SwiftUI

struct CalendarSidebarView: View {
    var viewModel: CalendarViewModel

    var body: some View {
        List {
            CalendarManagerView(viewModel: viewModel)

            Section("Быстрый доступ") {
                Button {
                    Task { await viewModel.syncAllProviders() }
                } label: {
                    Label("Синхронизировать календари", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSyncing)

                Button {
                    viewModel.selectedDate = Date()
                    viewModel.viewMode = .day
                } label: {
                    Label("Сегодня", systemImage: "star.fill")
                        .foregroundColor(.orange)
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.selectedDate = Date()
                    viewModel.viewMode = .week
                } label: {
                    Label("Эта неделя", systemImage: "calendar.badge.clock")
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.selectedDate = Date()
                    viewModel.viewMode = .month
                } label: {
                    Label("Этот месяц", systemImage: "calendar")
                        .foregroundColor(.purple)
                }
                .buttonStyle(.plain)
            }

            Section("Ближайшие события") {
                UpcomingEventsSection(viewModel: viewModel)
            }

            Section {
                MiniCalendarView(
                    selectedDate: viewModel.selectedDate,
                    onSelect: { viewModel.selectedDate = $0 }
                )
            }
        }
        .listStyle(.sidebar)
    }
}

/// Пять ближайших событий. Вынесено отдельно, чтобы список пересчитывался
/// только при изменении событий, а не при каждом действии в сайдбаре.
private struct UpcomingEventsSection: View {
    var viewModel: CalendarViewModel

    var body: some View {
        let upcomingEvents = viewModel.upcomingEvents(limit: 5)

        if upcomingEvents.isEmpty {
            Text("Нет предстоящих событий")
                .foregroundColor(.gray)
                .font(.caption)
        } else {
            ForEach(upcomingEvents) { event in
                Button {
                    viewModel.selectedDate = event.startDate
                    viewModel.viewMode = .day
                    viewModel.selectEvent(event)
                } label: {
                    HStack {
                        Circle()
                            .fill(viewModel.color(for: event))
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title.isEmpty ? "Новое событие" : event.title)
                                .font(.caption)
                                .foregroundColor(event.title.isEmpty ? .secondary : .primary)
                                .lineLimit(1)

                            Text(upcomingSubtitle(for: event))
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(event.title), \(upcomingSubtitle(for: event))")
            }
        }
    }

    private func upcomingSubtitle(for event: CalendarEvent) -> String {
        if event.isAllDay {
            return "\(event.startDate.dayString()), весь день"
        }
        return "\(event.startDate.dayString()), \(event.startDate.timeString())"
    }
}

/// Компактный месячный календарь для навигации.
///
/// Показываемый месяц следует за `selectedDate` (переход стрелками в тулбаре
/// или из другого вида перелистывает и его), но пользователь может листать
/// месяцы и независимо — до следующего изменения выбранной даты.
struct MiniCalendarView: View {
    let selectedDate: Date
    let onSelect: (Date) -> Void

    private let weekDays = Calendar.current.orderedWeekdaySymbols(.short)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    @State private var displayMonth: Date

    init(selectedDate: Date, onSelect: @escaping (Date) -> Void) {
        self.selectedDate = selectedDate
        self.onSelect = onSelect
        _displayMonth = State(initialValue: selectedDate.startOfMonth())
    }

    private var weeks: [[Date]] {
        displayMonth.getAllWeeksInMonth()
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    displayMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayMonth) ?? displayMonth
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Предыдущий месяц")

                Spacer()

                Text(displayMonth.monthYearString())
                    .font(.caption)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    displayMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayMonth) ?? displayMonth
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Следующий месяц")
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(weekDays.enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(weeks.flatMap { $0 }.enumerated()), id: \.offset) { _, date in
                    if date == Date.distantPast {
                        Text("")
                            .frame(width: 20, height: 20)
                    } else {
                        MiniCalendarDayCell(
                            date: date,
                            isToday: Calendar.current.isDateInToday(date),
                            isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate),
                            isCurrentMonth: Calendar.current.isDate(date, equalTo: displayMonth, toGranularity: .month),
                            onSelect: { onSelect(date) }
                        )
                    }
                }
            }
        }
        .padding(8)
        .onChange(of: selectedDate) { _, newValue in
            let newMonth = newValue.startOfMonth()
            if newMonth != displayMonth {
                displayMonth = newMonth
            }
        }
    }
}

private struct MiniCalendarDayCell: View {
    let date: Date
    let isToday: Bool
    let isSelected: Bool
    let isCurrentMonth: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Text(date.shortDayString())
                .font(.system(size: 10))
                .foregroundColor(isToday ? .white : (isCurrentMonth ? .primary : .gray))
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(isToday ? Color.red : (isSelected ? Color.blue.opacity(0.3) : Color.clear))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.dayString())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
