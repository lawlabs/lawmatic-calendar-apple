//
//  YearView.swift
//  CalendarTest45
//
//  Created by Sergey on 30.09.2025.
//

import SwiftUI

struct YearView: View {
    var viewModel: CalendarViewModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 28, alignment: .top), count: 3)

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
            VStack(alignment: .leading, spacing: 20) {
                Text(viewModel.selectedDate.yearOnlyString())
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.red)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Divider()
                    .padding(.horizontal, 20)

                LazyVGrid(columns: columns, spacing: 30) {
                    ForEach(monthsInYear, id: \.self) { month in
                        MiniMonthView(
                            month: month,
                            viewModel: viewModel
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
    }
}

struct MiniMonthView: View {
    let month: Date
    var viewModel: CalendarViewModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    private let weekDays = Calendar.current.orderedWeekdaySymbols(.veryShort)

    var weeks: [[Date]] {
        month.getAllWeeksInMonth()
    }

    var monthName: String {
        month.monthYearString().components(separatedBy: " ").first ?? ""
    }

    private var isSelectedMonth: Bool {
        Calendar.current.isDate(month, equalTo: viewModel.selectedDate, toGranularity: .month)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(monthName)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(isSelectedMonth ? .red : .primary)
                .padding(.bottom, 2)

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(weekDays.enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.65))
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(weeks.flatMap { $0 }.enumerated()), id: \.offset) { _, date in
                    if date == Date.distantPast {
                        Text("")
                            .frame(width: 22, height: 26)
                    } else {
                        MiniDayCellWithPopover(
                            date: date,
                            viewModel: viewModel,
                            isCurrentMonth: Calendar.current.isDate(date, equalTo: month, toGranularity: .month)
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Mini Day Cell with Popover

struct MiniDayCellWithPopover: View {
    let date: Date
    var viewModel: CalendarViewModel
    let isCurrentMonth: Bool

    @State private var showingPopover = false

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    private var isSelectedDay: Bool {
        Calendar.current.isDate(date, equalTo: viewModel.selectedDate, toGranularity: .day)
    }

    private var hasEvents: Bool {
        viewModel.hasEvents(on: date)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(date.shortDayString())
                .font(.system(size: 11, weight: isToday ? .bold : .regular))
                .foregroundColor(dayForegroundColor)
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(dayBackgroundColor)
                )
                .padding(.top, 1)

            Circle()
                .fill(hasEvents ? eventIndicatorColor : Color.clear)
                .frame(width: 3.5, height: 3.5)
                .padding(.top, 2)
        }
        .frame(width: 22, height: 26, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectedDate = date
            viewModel.clearSelection()
            if hasEvents {
                showingPopover = true
            }
        }
        .popover(isPresented: $showingPopover, arrowEdge: .trailing) {
            DayEventsPopover(
                date: date,
                events: viewModel.events(for: date),
                viewModel: viewModel
            )
        }
    }

    private var dayForegroundColor: Color {
        if isToday {
            return .white
        }

        if isSelectedDay {
            return .red
        }

        return isCurrentMonth ? .primary : .gray.opacity(0.45)
    }

    private var dayBackgroundColor: Color {
        if isToday {
            return .red
        }

        return .clear
    }

    private var eventIndicatorColor: Color {
        if isToday {
            return .red
        }

        return isSelectedDay ? .red : .blue
    }
}

// MARK: - Day Events Popover (как в Apple Calendar)

struct DayEventsPopover: View {
    let date: Date
    let events: [CalendarEvent]
    var viewModel: CalendarViewModel

    /// Заголовок даты: "5 февраля, четверг"
    private var dateTitle: String {
        date.dayString()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Заголовок с датой
            Text(dateTitle)
                .font(.headline)
                .padding(.bottom, 4)

            // Список событий
            ForEach(events) { event in
                PopoverEventRow(
                    event: event,
                    color: viewModel.color(for: event)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.selectEvent(event)
                }
            }
        }
        .background(
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.clearSelection()
                }
        )
        .padding(12)
        .frame(minWidth: 280, maxWidth: 400)
    }
}

// MARK: - Popover Event Row (вертикальная линия + название + время)

struct PopoverEventRow: View {
    let event: CalendarEvent
    let color: Color

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // Вертикальная цветная линия
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 4, height: 18)

            if event.isAllDay {
                Text(event.title)
                    .font(.system(size: 13))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("весь день")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            } else {
                // Название события
                Text(event.title)
                    .font(.system(size: 13))
                    .lineLimit(1)

                Spacer(minLength: 8)

                // Время события
                Text(event.startDate.timeString())
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.gray.opacity(0.1) : Color.clear)
        )
        .onHoverIfSupported { hovering in
            isHovered = hovering
        }
    }
}
