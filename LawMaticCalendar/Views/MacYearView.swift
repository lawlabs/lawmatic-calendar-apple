#if os(macOS)
import SwiftUI

struct MacYearView: View {
    @ObservedObject var viewModel: CalendarViewModel

    let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var monthsInYear: [Date] {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: viewModel.selectedDate)

        return (1...12).compactMap { month in
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 1
            return calendar.date(from: components)
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(monthsInYear, id: \.self) { month in
                    MacMiniMonthView(
                        month: month,
                        viewModel: viewModel
                    )
                }
            }
            .padding()
        }
    }
}

struct MacMiniMonthView: View {
    let month: Date
    @ObservedObject var viewModel: CalendarViewModel

    let weekDays = ["В", "П", "В", "С", "Ч", "П", "С"]
    let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var weeks: [[Date]] {
        month.getAllWeeksInMonth()
    }

    var monthName: String {
        month.monthYearString().components(separatedBy: " ").first ?? ""
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(monthName)
                .font(.headline)
                .padding(.bottom, 4)

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(weekDays.enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(weeks.flatMap { $0 }.enumerated()), id: \.offset) { _, date in
                    if date == Date.distantPast {
                        Text("")
                            .frame(width: 24, height: 24)
                    } else {
                        MacMiniDayCellWithPopover(
                            date: date,
                            viewModel: viewModel,
                            isCurrentMonth: Calendar.current.isDate(date, equalTo: month, toGranularity: .month)
                        )
                    }
                }
            }
        }
        .padding(12)
        .background(Color.calendarControlBackground)
        .cornerRadius(8)
    }
}

struct MacMiniDayCellWithPopover: View {
    let date: Date
    @ObservedObject var viewModel: CalendarViewModel
    let isCurrentMonth: Bool

    @State private var showingPopover = false

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    private var dayEvents: [CalendarEvent] {
        viewModel.events(for: date)
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(date.shortDayString())
                .font(.system(size: 11))
                .fontWeight(isToday ? .bold : .regular)
                .foregroundColor(isToday ? .white : (isCurrentMonth ? .primary : .gray))
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(isToday ? Color.red : Color.clear)
                )

            if !dayEvents.isEmpty {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 4, height: 4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectedDate = date
            viewModel.clearSelection()
            if !dayEvents.isEmpty {
                showingPopover = true
            }
        }
        .popover(isPresented: $showingPopover, arrowEdge: .trailing) {
            DayEventsPopover(
                date: date,
                events: dayEvents,
                viewModel: viewModel
            )
        }
    }
}
#endif
