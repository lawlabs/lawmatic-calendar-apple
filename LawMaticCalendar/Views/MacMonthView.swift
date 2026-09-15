#if os(macOS)
import SwiftUI

struct MacMonthView: View {
    var viewModel: CalendarViewModel

    private let weekDays = Calendar.current.orderedWeekdaySymbols(.short)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    /// Месяцы вокруг якоря. Якорь фиксируется при первом показе, а диапазон
    /// только расширяется по краям, когда пользователь уходит далеко, —
    /// пересоздание массива вокруг новой даты сдвигало бы содержимое над
    /// текущей позицией и вызывало скачок скролла.
    @State private var anchorMonth: Date
    @State private var monthOffsets: ClosedRange<Int> = -24 ... 24
    private static let edgeMargin = 6

    init(viewModel: CalendarViewModel) {
        self.viewModel = viewModel
        _anchorMonth = State(initialValue: viewModel.selectedDate.startOfMonth())
    }

    private var allMonths: [Date] {
        monthOffsets.compactMap { offset in
            Calendar.current.date(byAdding: .month, value: offset, to: anchorMonth)
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
                        proxy.scrollTo(monthId(for: viewModel.selectedDate.startOfMonth()), anchor: .top)
                    }
                }
                .onChange(of: viewModel.selectedDate) { oldDate, newDate in
                    let newMonth = newDate.startOfMonth()
                    guard newMonth != oldDate.startOfMonth() else { return }
                    extendRangeIfNeeded(for: newMonth)
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(monthId(for: newMonth), anchor: .top)
                        }
                    }
                }
            }
        }
    }

    private func extendRangeIfNeeded(for month: Date) {
        let offset = Calendar.current.dateComponents([.month], from: anchorMonth, to: month).month ?? 0
        if offset - Self.edgeMargin < monthOffsets.lowerBound {
            monthOffsets = (offset - 24) ... monthOffsets.upperBound
        } else if offset + Self.edgeMargin > monthOffsets.upperBound {
            monthOffsets = monthOffsets.lowerBound ... (offset + 24)
        }
    }

    private func monthId(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return "month-\(components.year ?? 0)-\(components.month ?? 0)"
    }
}

struct MacMonthGridSection: View {
    let month: Date
    var viewModel: CalendarViewModel
    let columns: [GridItem]

    private var weeks: [[Date]] {
        month.getAllWeeksInMonth()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(month.monthYearString())
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
                            dayCell(for: date)
                                .frame(height: 110)
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func dayCell(for date: Date) -> some View {
        let events = viewModel.events(for: date)
        let selectedID = viewModel.selectedEventId
        let rows = events.map { event in
            MonthEventRowModel(
                id: event.id,
                title: event.title,
                isAllDay: event.isAllDay,
                timeText: event.startDate.timeString(),
                color: viewModel.color(for: event),
                isSelected: event.id == selectedID
            )
        }

        return MacMonthDayCell(
            date: date,
            rows: rows,
            isCurrentMonth: Calendar.current.isDate(date, equalTo: month, toGranularity: .month),
            isToday: Calendar.current.isDateInToday(date),
            isSelected: Calendar.current.isDate(date, equalTo: viewModel.selectedDate, toGranularity: .day),
            onEventTap: { eventID in
                if let event = events.first(where: { $0.id == eventID }) {
                    viewModel.selectEvent(event)
                }
            },
            onDayTap: {
                viewModel.selectedDate = date
                viewModel.clearSelection()
            },
            onDayDoubleTap: {
                viewModel.selectedDate = date
                viewModel.viewMode = .day
            }
        )
    }
}

/// Плоская модель строки события в ячейке месяца — ячейка не зависит от VM.
struct MonthEventRowModel: Identifiable, Equatable {
    let id: UUID
    let title: String
    let isAllDay: Bool
    let timeText: String
    let color: Color
    let isSelected: Bool
}

struct MacMonthDayCell: View {
    let date: Date
    let rows: [MonthEventRowModel]
    let isCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let onEventTap: (UUID) -> Void
    let onDayTap: () -> Void
    let onDayDoubleTap: () -> Void

    private let maxVisibleEvents = 4
    @State private var isOverflowPresented = false

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

            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(rows.prefix(maxVisibleEvents)) { row in
                        MacMonthEventRow(row: row)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onEventTap(row.id)
                            }
                    }

                    if rows.count > maxVisibleEvents {
                        Button {
                            isOverflowPresented = true
                        } label: {
                            Text("+ ещё \(rows.count - maxVisibleEvents)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .padding(.leading, 4)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $isOverflowPresented, arrowEdge: .trailing) {
                            MacMonthOverflowPopover(
                                date: date,
                                rows: rows,
                                onEventTap: { id in
                                    isOverflowPresented = false
                                    onEventTap(id)
                                }
                            )
                        }
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
        .onTapGesture(count: 2) {
            onDayDoubleTap()
        }
        .onTapGesture {
            onDayTap()
        }
        .overlay(
            Rectangle()
                .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let base = date.dayString()
        if rows.isEmpty { return base }
        return "\(base), событий: \(rows.count)"
    }
}

struct MacMonthEventRow: View {
    let row: MonthEventRowModel

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            if row.isAllDay {
                Text(row.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(row.color.eventTextColor(isSelected: true, colorScheme: colorScheme))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(row.color.opacity(row.isSelected ? 1.0 : 0.85))
                    )
            } else {
                RoundedRectangle(cornerRadius: 1)
                    .fill(row.color)
                    .frame(width: 3, height: 14)

                Text(row.title)
                    .font(.system(size: 10))
                    .foregroundColor(row.isSelected
                        ? row.color.eventTextColor(isSelected: true, colorScheme: colorScheme)
                        : .primary)
                    .lineLimit(1)

                Spacer(minLength: 2)

                Text(row.timeText)
                    .font(.system(size: 10))
                    .foregroundColor(row.isSelected
                        ? row.color.eventTextColor(isSelected: true, colorScheme: colorScheme).opacity(0.8)
                        : .secondary)
            }
        }
        .padding(.horizontal, 3)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(row.isSelected ? row.color.opacity(0.95) : Color.clear)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.isAllDay ? "\(row.title), весь день" : "\(row.title), \(row.timeText)")
        .accessibilityAddTraits(.isButton)
    }
}

/// Список всех событий дня для «+ ещё N».
private struct MacMonthOverflowPopover: View {
    let date: Date
    let rows: [MonthEventRowModel]
    let onEventTap: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(date.dayString())
                .font(.headline)
                .padding(.bottom, 4)

            ForEach(rows) { row in
                MacMonthEventRow(row: row)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onEventTap(row.id)
                    }
            }
        }
        .padding(12)
        .frame(minWidth: 240, maxWidth: 360)
    }
}
#endif
