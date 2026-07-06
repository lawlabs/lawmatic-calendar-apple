import SwiftUI

struct CalendarSidebarView: View {
    @ObservedObject var viewModel: CalendarViewModel

    var body: some View {
        List {
            CalendarManagerView(viewModel: viewModel)

            Section("Быстрый доступ") {
                Button {
                    Task { await viewModel.syncTasksFromLegalic() }
                } label: {
                    Label("Загрузить задачи LEGALIC", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLegalicSyncing)

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
                let upcomingEvents = viewModel.events
                    .filter { $0.startDate >= Date() }
                    .sorted { $0.startDate < $1.startDate }
                    .prefix(5)

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
                                    Text(event.title)
                                        .font(.caption)
                                        .lineLimit(1)

                                    Text(event.startDate.dayString())
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                MiniCalendarView(viewModel: viewModel)
            }
        }
        .listStyle(.sidebar)
    }
}

struct MiniCalendarView: View {
    @ObservedObject var viewModel: CalendarViewModel

    private let weekDays = ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    @State private var displayMonth = Date()

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
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekDays, id: \.self) { day in
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
                        Button {
                            viewModel.selectedDate = date
                        } label: {
                            Text(date.shortDayString())
                                .font(.system(size: 10))
                                .foregroundColor(
                                    Calendar.current.isDateInToday(date) ? .white :
                                    Calendar.current.isDate(date, equalTo: displayMonth, toGranularity: .month) ? .primary : .gray
                                )
                                .frame(width: 20, height: 20)
                                .background(
                                    Circle()
                                        .fill(
                                            Calendar.current.isDateInToday(date) ? Color.red :
                                            Calendar.current.isDate(date, equalTo: viewModel.selectedDate, toGranularity: .day) ? Color.blue.opacity(0.3) : Color.clear
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(8)
    }
}
