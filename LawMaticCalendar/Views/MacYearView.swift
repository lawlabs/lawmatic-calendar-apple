#if os(macOS)
import SwiftUI

struct MacYearView: View {
    var viewModel: CalendarViewModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    private var monthsInYear: [Date] {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: viewModel.selectedDate)

        return (1...12).compactMap { month in
            calendar.date(from: DateComponents(year: year, month: month, day: 1))
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
    var viewModel: CalendarViewModel

    private let weekDays = Calendar.current.orderedWeekdaySymbols(.veryShort)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    private var weeks: [[Date]] {
        month.getAllWeeksInMonth()
    }

    private var monthName: String {
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
                        MacMiniDayCell(
                            date: date,
                            isToday: Calendar.current.isDateInToday(date),
                            isCurrentMonth: Calendar.current.isDate(date, equalTo: month, toGranularity: .month),
                            hasEvents: viewModel.hasEvents(on: date),
                            onTap: {
                                viewModel.selectedDate = date
                                viewModel.clearSelection()
                            },
                            onDoubleTap: {
                                viewModel.selectedDate = date
                                viewModel.viewMode = .day
                            },
                            popover: {
                                DayEventsPopover(
                                    date: date,
                                    events: viewModel.events(for: date),
                                    viewModel: viewModel
                                )
                            }
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

/// Ячейка дня в годовом виде. Клик выбирает день и, если есть события,
/// показывает их список; двойной клик открывает дневной вид.
private struct MacMiniDayCell<Popover: View>: View {
    let date: Date
    let isToday: Bool
    let isCurrentMonth: Bool
    let hasEvents: Bool
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    @ViewBuilder let popover: () -> Popover

    @State private var showingPopover = false

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

            Circle()
                .fill(hasEvents ? Color.blue : Color.clear)
                .frame(width: 4, height: 4)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            showingPopover = false
            onDoubleTap()
        }
        .onTapGesture {
            onTap()
            if hasEvents {
                showingPopover = true
            }
        }
        .popover(isPresented: $showingPopover, arrowEdge: .trailing, content: popover)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hasEvents ? "\(date.dayString()), есть события" : date.dayString())
        .accessibilityAddTraits(.isButton)
    }
}
#endif
