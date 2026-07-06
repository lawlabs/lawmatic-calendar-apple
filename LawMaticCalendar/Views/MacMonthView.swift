#if os(macOS)
import SwiftUI

struct MacMonthView: View {
    @ObservedObject var viewModel: CalendarViewModel

    let weekDays = ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]
    let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private static let monthRange = -24...24
    private let allMonths: [Date]
    private let baseMonth: Date

    init(viewModel: CalendarViewModel) {
        self.viewModel = viewModel
        let start = viewModel.selectedDate.startOfMonth()
        self.baseMonth = start
        self.allMonths = Self.monthRange.compactMap { offset in
            Calendar.current.date(byAdding: .month, value: offset, to: start)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(weekDays.enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 4)

            Divider()

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(allMonths, id: \.self) { month in
                            MacMonthGridSection(
                                month: month,
                                viewModel: viewModel,
                                columns: columns
                            )
                            .id(monthId(for: month))
                        }
                    }
                }
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo(monthId(for: baseMonth), anchor: .top)
                    }
                }
                .onChange(of: viewModel.selectedDate) { _, newDate in
                    let newMonth = newDate.startOfMonth()
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(monthId(for: newMonth), anchor: .top)
                        }
                    }
                }
            }
        }
    }

    private func monthId(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return "month-\(components.year ?? 0)-\(components.month ?? 0)"
    }
}

struct MacMonthGridSection: View {
    let month: Date
    @ObservedObject var viewModel: CalendarViewModel
    let columns: [GridItem]

    var weeks: [[Date]] {
        month.getAllWeeksInMonth()
    }

    var monthTitle: String {
        month.monthYearString()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(monthTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.leading, 8)
                    .padding(.vertical, 10)

                Spacer()
            }
            .padding(.horizontal, 4)

            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                        if date == Date.distantPast {
                            Color.clear
                                .frame(height: 110)
                        } else {
                            MacMonthDayCell(
                                date: date,
                                events: viewModel.events(for: date),
                                viewModel: viewModel,
                                isCurrentMonth: Calendar.current.isDate(date, equalTo: month, toGranularity: .month),
                                isToday: Calendar.current.isDateInToday(date),
                                isSelected: Calendar.current.isDate(date, equalTo: viewModel.selectedDate, toGranularity: .day),
                                onEventTap: { event in
                                    viewModel.selectEvent(event)
                                },
                                onDayTap: {
                                    viewModel.selectedDate = date
                                    viewModel.clearSelection()
                                }
                            )
                            .frame(height: 110)
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

struct MacMonthDayCell: View {
    let date: Date
    let events: [CalendarEvent]
    @ObservedObject var viewModel: CalendarViewModel
    let isCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let onEventTap: (CalendarEvent) -> Void
    let onDayTap: () -> Void

    private let maxVisibleEvents = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(date.shortDayString())
                    .font(.system(size: 14, weight: isToday ? .bold : .regular))
                    .foregroundColor(
                        isToday ? .white :
                            isCurrentMonth ? .primary : .gray.opacity(0.5)
                    )
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(isToday ? Color.red : Color.clear)
                    )
                    .padding(.top, 4)
                    .padding(.leading, 4)

                Spacer()
            }

            if !events.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(events.prefix(maxVisibleEvents)) { event in
                        MacMonthEventRow(
                            event: event,
                            color: viewModel.color(for: event),
                            isSelected: viewModel.selectedEvent?.id == event.id
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onEventTap(event)
                        }
                    }

                    if events.count > maxVisibleEvents {
                        Text("+ ещё \(events.count - maxVisibleEvents)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .background(
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    isSelected && !isToday ?
                        Color.blue.opacity(0.08) :
                        Color.clear
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onDayTap()
        }
        .overlay(
            Rectangle()
                .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
        )
    }
}

struct MacMonthEventRow: View {
    let event: CalendarEvent
    let color: Color
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 4) {
            if event.isAllDay {
                Text(event.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.opacity(isSelected ? 1.0 : 0.85))
                    )
            } else {
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 3, height: 14)

                Text(event.title)
                    .font(.system(size: 10))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer(minLength: 2)

                Text(event.startDate.timeString())
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 3)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(isSelected ? color.opacity(0.95) : Color.clear)
        )
    }
}
#endif
