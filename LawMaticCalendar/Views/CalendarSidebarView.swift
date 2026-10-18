import Kalends
import SwiftUI

struct CalendarSidebarView: View {
    @Bindable var viewModel: CalendarViewModel

    var body: some View {
        List {
            CalendarManagerView(viewModel: viewModel)

            Section("Быстрый доступ") {
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
                MiniCalendarView(selectedDate: $viewModel.selectedDate)
                    .kalendsDays(viewModel.kalendsDayConfiguration)
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
