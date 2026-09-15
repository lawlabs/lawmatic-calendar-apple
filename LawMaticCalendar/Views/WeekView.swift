//
//  WeekView.swift
//  CalendarTest45
//
//  Created by Sergey on 30.09.2025.
//

import SwiftUI

struct WeekView: View {
    var viewModel: CalendarViewModel
    let hours = Array(0...23)
    let hourHeight: CGFloat = 60

    var daysOfWeek: [Date] {
        viewModel.selectedDate.getDaysOfWeek()
    }

    /// Проверяем, есть ли целодневные события на этой неделе
    private var hasAllDayEvents: Bool {
        daysOfWeek.contains { day in
            !viewModel.events(for: day).filter({ $0.isAllDay }).isEmpty
        }
    }

    /// Начальная прокрутка: к текущему часу (минус два), если неделя содержит
    /// сегодня, иначе к началу рабочего дня.
    private var initialScrollHour: Int {
        if daysOfWeek.contains(where: { Calendar.current.isDateInToday($0) }) {
            return max(0, Calendar.current.component(.hour, from: Date()) - 2)
        }
        return 8
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section(header: weekHeader) {
                        WeekGridView(
                            viewModel: viewModel,
                            hours: hours,
                            hourHeight: hourHeight,
                            daysOfWeek: daysOfWeek
                        )
                        .background(
                            VStack(spacing: 0) {
                                ForEach(hours, id: \.self) { hour in
                                    Color.clear
                                        .frame(height: hourHeight)
                                        .id("week-hour-\(hour)")
                                }
                            }
                        )
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo("week-hour-\(initialScrollHour)", anchor: .top)
                }
            }
        }
    }

    @ViewBuilder
    private var weekHeader: some View {
        VStack(spacing: 0) {
            WeekHeaderView(daysOfWeek: daysOfWeek)

            if hasAllDayEvents {
                WeekAllDaySection(
                    viewModel: viewModel,
                    daysOfWeek: daysOfWeek
                )
            }

            Divider()
        }
        .background(Color.calendarWindowBackground)
    }
}

// MARK: - Week All Day Section

struct WeekAllDaySection: View {
    var viewModel: CalendarViewModel
    let daysOfWeek: [Date]

    var body: some View {
        HStack(spacing: 0) {
            // Левая колонка — структура как в WeekGridBackground:
            // .frame(width: 50) + .padding(.trailing, 4) снаружи = 54pt общая ширина
            Text("весь день")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 50, alignment: .trailing)
                .padding(.trailing, 4)

            // Ячейки по дням — такой же ForEach как в сетке
            ForEach(daysOfWeek, id: \.self) { day in
                let allDayEvents = viewModel.events(for: day).filter { $0.isAllDay }

                ZStack {
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.clearSelection()
                        }

                    VStack(spacing: 2) {
                        ForEach(allDayEvents) { event in
                            WeekAllDayEventCell(
                                event: event,
                                color: viewModel.color(for: event),
                                isSelected: viewModel.selectedEventId == event.id
                            )
                            .padding(.horizontal, 2)
                            .onTapGesture {
                                viewModel.selectEvent(event)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .clipped()
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Week All Day Event Cell

struct WeekAllDayEventCell: View {
    let event: CalendarEvent
    let color: Color
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var textColor: Color {
        color.eventTextColor(isSelected: isSelected, colorScheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Яркая вертикальная полоска слева (как в Apple Calendar)
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 3)

            Text(event.title)
                .font(.system(size: 10))
                .fontWeight(.medium)
                .foregroundColor(textColor)
                .lineLimit(1)
                .padding(.horizontal, 3)

            Spacer(minLength: 0)
        }
        .frame(height: 18)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(isSelected ? 0.5 : 0.2))
        )
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(color.opacity(isSelected ? 0.6 : 0), lineWidth: 1)
        )
    }
}

struct WeekHeaderView: View {
    let daysOfWeek: [Date]

    var body: some View {
        HStack(spacing: 0) {
            // Левая колонка — как в WeekGridBackground: 50pt + 4pt padding = 54pt
            Text("")
                .frame(width: 50)
                .padding(.trailing, 4)

            ForEach(daysOfWeek, id: \.self) { day in
                WeekDayHeader(day: day)
            }
        }
        .padding(.vertical, 8)
    }
}

struct WeekDayHeader: View {
    let day: Date

    var body: some View {
        VStack(spacing: 4) {
            Text(day.shortWeekdayString())
                .font(.caption)
                .foregroundColor(.gray)

            let isToday = Calendar.current.isDateInToday(day)
            Text(day.shortDayString())
                .font(.headline)
                .foregroundColor(isToday ? .red : .primary)
                .padding(4)
                .background(
                    Circle()
                        .fill(isToday ? Color.red.opacity(0.1) : Color.clear)
                )
        }
        .frame(maxWidth: .infinity)
    }
}

struct WeekGridView: View {
    var viewModel: CalendarViewModel
    let hours: [Int]
    let hourHeight: CGFloat
    let daysOfWeek: [Date]

    var body: some View {
        ZStack(alignment: .topLeading) {
            WeekGridBackground(hours: hours, hourHeight: hourHeight)
            WeekEventsOverlay(
                viewModel: viewModel,
                daysOfWeek: daysOfWeek,
                hourHeight: hourHeight,
                totalHeight: CGFloat(hours.count) * hourHeight
            )

            // Индикатор текущего времени для недели
            if daysOfWeek.contains(where: { Calendar.current.isDateInToday($0) }) {
                CurrentTimeIndicator(hourHeight: hourHeight)
            }
        }
        .frame(minHeight: CGFloat(hours.count) * hourHeight)
    }
}

struct WeekGridBackground: View {
    let hours: [Int]
    let hourHeight: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(hours, id: \.self) { hour in
                    Text(String(format: "%02d:00", hour))
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(width: 50, height: hourHeight, alignment: .topTrailing)
                        .padding(.trailing, 4)
                }
            }

            TimeGridLines(hourHeight: hourHeight, hourCount: hours.count, columnCount: 7)
        }
    }
}

struct WeekEventsOverlay: View {
    var viewModel: CalendarViewModel
    let daysOfWeek: [Date]
    let hourHeight: CGFloat
    let totalHeight: CGFloat // Фиксированная высота для предотвращения пересчёта layout

    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 54)  // 50pt + 4pt padding

            ForEach(Array(daysOfWeek.enumerated()), id: \.offset) { _, day in
                WeekDayEvents(
                    viewModel: viewModel,
                    day: day,
                    hourHeight: hourHeight,
                    totalHeight: totalHeight
                )
            }
        }
        .frame(height: totalHeight)
    }
}

struct WeekDayEvents: View {
    var viewModel: CalendarViewModel
    let day: Date
    let hourHeight: CGFloat
    let totalHeight: CGFloat // Фиксированная высота контейнера
    @State private var creationDragStartY: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            let dayWidth = geometry.size.width

            ZStack(alignment: .topLeading) {
                // Прозрачный прямоугольник для фиксации размера контейнера
                Color.clear

                // Двойной клик по пустому месту создаёт черновик события
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(dragCreationGesture)
                    .simultaneousGesture(doubleTapCreationGesture)
                    .simultaneousGesture(backgroundSelectionClearGesture)

                let dayEvents = viewModel.events(for: day).filter { !$0.isAllDay }
                let layoutInfos = EventLayoutCalculator.calculateLayout(
                    for: dayEvents,
                    on: day,
                    containerWidth: dayWidth,
                    hourHeight: hourHeight
                )

                ForEach(layoutInfos, id: \.event.id) { layoutInfo in
                    DraggableEventView(
                        event: layoutInfo.event,
                        displayDate: day,
                        color: viewModel.color(for: layoutInfo.event),
                        hourHeight: hourHeight,
                        containerWidth: dayWidth,
                        dayWidth: dayWidth,
                        style: .week,
                        xFraction: layoutInfo.xFraction,
                        widthFraction: layoutInfo.widthFraction,
                        zIndexPriority: layoutInfo.zIndexPriority,
                        isSelected: viewModel.selectedEventId == layoutInfo.event.id,
                        onEventUpdate: { updatedEvent in
                            viewModel.updateEvent(updatedEvent)
                        },
                        onEventTap: {
                            viewModel.selectEvent(layoutInfo.event)
                        }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: totalHeight)  // Flexible width like other sections
        // Не используем clipped() чтобы события могли выходить за границы при перетаскивании
    }

    private func startDate(forVerticalLocation y: CGFloat) -> Date {
        let calendar = Calendar.current
        let clampedY = min(max(0, y), totalHeight)
        let rawMinutes = Int((clampedY / hourHeight) * 60)
        let roundedMinutes = min(23 * 60 + 45, ((rawMinutes + 7) / 15) * 15)
        let hour = roundedMinutes / 60
        let minute = roundedMinutes % 60

        return calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: day
        ) ?? day
    }

    private var doubleTapCreationGesture: some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                let startDate = startDate(forVerticalLocation: value.location.y)
                viewModel.createNewEvent(
                    at: startDate,
                    duration: viewModel.defaultDurationForQuickCreate(at: startDate)
                )
            }
    }

    private var backgroundSelectionClearGesture: some Gesture {
        SpatialTapGesture(count: 1)
            .onEnded { _ in
                viewModel.clearSelection()
            }
    }

    private var dragCreationGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                let startY = creationDragStartY ?? value.startLocation.y
                creationDragStartY = startY

                guard abs(value.translation.height) >= 8 else { return }

                viewModel.updatePendingNewEvent(
                    startDate: startDate(forVerticalLocation: startY),
                    endDate: startDate(forVerticalLocation: value.location.y)
                )
            }
            .onEnded { _ in
                creationDragStartY = nil
            }
    }
}
