//
//  MonthView.swift
//  CalendarTest45
//
//  Created by Sergey on 30.09.2025.
//

import SwiftUI

struct MonthView: View {
    @ObservedObject var viewModel: CalendarViewModel

    let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private static let monthRange = -24...24
    private let allMonths: [Date]
    private let baseMonth: Date

    private var weekDays: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let firstWeekdayIndex = max(0, calendar.firstWeekday - 1)
        return Array(symbols[firstWeekdayIndex...] + symbols[..<firstWeekdayIndex])
    }

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
                        .font(.system(size: 13, weight: .medium))
                        .fontWeight(.medium)
                        .foregroundColor(.secondary.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
            }
            .padding(.horizontal, 8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(allMonths, id: \.self) { month in
                            MonthGridSection(
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

// MARK: - Month Grid Section (один месяц в скролле)

struct MonthGridSection: View {
    let month: Date
    @ObservedObject var viewModel: CalendarViewModel
    let columns: [GridItem]

    private static let monthOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL"
        return formatter
    }()

    var weeks: [[Date]] {
        month.getAllWeeksInMonth()
    }

    var monthTitle: String {
        let title = Self.monthOnlyFormatter.string(from: month).capitalized
        if Calendar.current.isDate(month, equalTo: viewModel.selectedDate, toGranularity: .year) {
            return title
        }

        return "\(title) \(month.yearOnlyString())"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(monthTitle)
                    .font(.system(size: 25, weight: .bold))
                    .fontWeight(.bold)
                    .padding(.leading, 12)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                Spacer()
            }
            .padding(.horizontal, 4)

            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                        if date == Date.distantPast {
                            Color.clear
                                .frame(height: 102)
                        } else {
                            MonthDayCell(
                                date: date,
                                events: viewModel.events(for: date),
                                viewModel: viewModel,
                                isCurrentMonth: Calendar.current.isDate(date, equalTo: month, toGranularity: .month),
                                isToday: Calendar.current.isDateInToday(date),
                                isSelected: Calendar.current.isDate(date, equalTo: viewModel.selectedDate, toGranularity: .day),
                                onDayTap: {
                                    viewModel.selectedDate = date
                                    viewModel.clearSelection()
                                }
                            )
                            .frame(height: 102)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }
}

// MARK: - Month Day Cell

struct MonthDayCell: View {
    let date: Date
    let events: [CalendarEvent]
    @ObservedObject var viewModel: CalendarViewModel
    let isCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let onDayTap: () -> Void

    private let maxVisibleIndicators = 3

    private var sortedEvents: [CalendarEvent] {
        events.sorted {
            if $0.isAllDay != $1.isAllDay {
                return $0.isAllDay && !$1.isAllDay
            }

            return $0.startDate < $1.startDate
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(date.shortDayString())
                    .font(.system(size: 16, weight: isToday ? .bold : .regular))
                    .foregroundColor(
                        isToday ? .white :
                        isCurrentMonth ? .primary : .gray.opacity(0.45)
                    )
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(dayBadgeBackground)
                    )
                    .padding(.top, 5)
                    .padding(.leading, 5)

                Spacer()
            }

            Spacer(minLength: 8)

            MonthEventIndicators(
                events: sortedEvents,
                viewModel: viewModel,
                maxVisibleIndicators: maxVisibleIndicators
            )
            .padding(.horizontal, 7)
            .padding(.bottom, 9)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onDayTap()
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.gray.opacity(0.08))
                .frame(height: 0.5)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.gray.opacity(0.05))
                .frame(width: 0.5)
        }
    }

    private var dayBadgeBackground: Color {
        if isToday {
            return .red
        }

        if isSelected {
            return Color.primary.opacity(0.06)
        }

        return .clear
    }
}

// MARK: - Month Event Indicators

struct MonthEventIndicators: View {
    let events: [CalendarEvent]
    @ObservedObject var viewModel: CalendarViewModel
    let maxVisibleIndicators: Int

    private var visibleEvents: [CalendarEvent] {
        Array(events.prefix(maxVisibleIndicators))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(visibleEvents) { event in
                RoundedRectangle(cornerRadius: 2)
                    .fill(viewModel.color(for: event).opacity(event.isAllDay ? 0.9 : 0.72))
                    .frame(height: event.isAllDay ? 5 : 4)
            }

            if events.count > maxVisibleIndicators {
                HStack(spacing: 2.5) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(Color.secondary.opacity(0.38))
                            .frame(width: 2.5, height: 2.5)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
