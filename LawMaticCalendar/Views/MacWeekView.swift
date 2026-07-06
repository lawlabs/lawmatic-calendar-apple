#if os(macOS)
//
//  WeekView.swift
//  CalendarTest45
//
//  Created by Sergey on 30.09.2025.
//

import Combine
import SwiftUI

struct MacWeekView: View {
    @ObservedObject var viewModel: CalendarViewModel
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

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section(header: weekHeader) {
                    MacWeekGridView(
                        viewModel: viewModel,
                        hours: hours,
                        hourHeight: hourHeight,
                        daysOfWeek: daysOfWeek
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var weekHeader: some View {
        VStack(spacing: 0) {
            MacWeekHeaderView(daysOfWeek: daysOfWeek)

            if hasAllDayEvents {
                MacWeekAllDaySection(
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

struct MacWeekAllDaySection: View {
    @ObservedObject var viewModel: CalendarViewModel
    let daysOfWeek: [Date]

    var body: some View {
        HStack(spacing: 0) {
            // Левая колонка — структура как в MacWeekGridBackground:
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
                            MacWeekAllDayEventCell(
                                event: event,
                                color: viewModel.color(for: event),
                                isSelected: viewModel.selectedEvent?.id == event.id
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

struct MacWeekAllDayEventCell: View {
    let event: CalendarEvent
    let color: Color
    let isSelected: Bool

    /// Цвет текста - более тёмный оттенок цвета календаря
    private var textColor: Color {
        color.mix(with: .black, by: 0.4)
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

struct MacWeekHeaderView: View {
    let daysOfWeek: [Date]

    var body: some View {
        HStack(spacing: 0) {
            // Левая колонка — как в MacWeekGridBackground: 50pt + 4pt padding = 54pt
            Text("")
                .frame(width: 50)
                .padding(.trailing, 4)

            ForEach(daysOfWeek, id: \.self) { day in
                MacWeekDayHeader(day: day)
            }
        }
        .padding(.vertical, 8)
    }
}

struct MacWeekDayHeader: View {
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

struct MacWeekGridView: View {
    @ObservedObject var viewModel: CalendarViewModel
    let hours: [Int]
    let hourHeight: CGFloat
    let daysOfWeek: [Date]

    var body: some View {
        ZStack(alignment: .topLeading) {
            MacWeekGridBackground(hours: hours, hourHeight: hourHeight)
            MacWeekEventsOverlay(
                viewModel: viewModel,
                daysOfWeek: daysOfWeek,
                hourHeight: hourHeight,
                totalHeight: CGFloat(hours.count) * hourHeight
            )

            // Индикатор текущего времени для недели
            if daysOfWeek.contains(where: { Calendar.current.isDateInToday($0) }) {
                MacWeekCurrentTimeIndicator(hourHeight: hourHeight)
            }
        }
        .frame(minHeight: CGFloat(hours.count) * hourHeight)
    }
}

struct MacWeekGridBackground: View {
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

            VStack(spacing: 0) {
                ForEach(hours, id: \.self) { _ in
                    HStack(spacing: 0) {
                        ForEach(0..<7) { index in
                            ZStack(alignment: .topTrailing) {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .frame(height: hourHeight)

                                // Горизонтальная линия сверху
                                Rectangle()
                                    .fill(Color.calendarSeparator)
                                    .frame(height: 1)
                                    .frame(maxWidth: .infinity)
                                    .offset(y: 0)

                                // Вертикальная линия справа (кроме последнего столбца)
                                if index < 6 {
                                    Rectangle()
                                        .fill(Color.calendarSeparator)
                                        .frame(width: 1)
                                        .frame(maxHeight: .infinity)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct MacWeekEventsOverlay: View {
    @ObservedObject var viewModel: CalendarViewModel
    let daysOfWeek: [Date]
    let hourHeight: CGFloat
    let totalHeight: CGFloat // Фиксированная высота для предотвращения пересчёта layout

    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 54)  // 50pt + 4pt padding

            ForEach(Array(daysOfWeek.enumerated()), id: \.offset) { _, day in
                MacWeekDayEvents(
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

struct MacWeekDayEvents: View {
    @ObservedObject var viewModel: CalendarViewModel
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
                    MacWeekDraggableEventView(
                        event: layoutInfo.event,
                        displayDate: day,
                        color: viewModel.color(for: layoutInfo.event),
                        hourHeight: hourHeight,
                        containerWidth: dayWidth,
                        dayWidth: dayWidth,
                        xFraction: layoutInfo.xFraction,
                        widthFraction: layoutInfo.widthFraction,
                        zIndexPriority: layoutInfo.zIndexPriority,
                        isSelected: viewModel.selectedEvent?.id == layoutInfo.event.id,
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

/// Полноценная версия для недельного вида с поддержкой перетаскивания между днями
struct MacWeekDraggableEventView: View {
    let event: CalendarEvent
    let displayDate: Date
    let color: Color
    let hourHeight: CGFloat
    let containerWidth: CGFloat
    let dayWidth: CGFloat        // Ширина одного дня для расчёта смещения
    let xFraction: CGFloat
    let widthFraction: CGFloat
    let zIndexPriority: Double
    let isSelected: Bool         // Выделено ли событие
    let onEventUpdate: (CalendarEvent) -> Void
    let onEventTap: () -> Void

    /// Инициализатор с параметрами наложений по умолчанию
    init(
        event: CalendarEvent,
        displayDate: Date,
        color: Color,
        hourHeight: CGFloat,
        containerWidth: CGFloat,
        dayWidth: CGFloat,
        xFraction: CGFloat = 0,
        widthFraction: CGFloat = 1,
        zIndexPriority: Double? = nil,
        isSelected: Bool = false,
        onEventUpdate: @escaping (CalendarEvent) -> Void,
        onEventTap: @escaping () -> Void
    ) {
        self.event = event
        self.displayDate = displayDate
        self.color = color
        self.hourHeight = hourHeight
        self.containerWidth = containerWidth
        self.dayWidth = dayWidth
        self.xFraction = xFraction
        self.widthFraction = widthFraction
        self.zIndexPriority = zIndexPriority ?? event.startDate.timeIntervalSince1970
        self.isSelected = isSelected
        self.onEventUpdate = onEventUpdate
        self.onEventTap = onEventTap
    }

    @State private var isDragging = false
    @State private var dragOffsetX: CGFloat = 0  // Горизонтальное смещение (между днями)
    @State private var dragOffsetY: CGFloat = 0  // Вертикальное смещение (время)
    @State private var isResizingTop = false
    @State private var topResizeOffset: CGFloat = 0
    @State private var isResizingBottom = false
    @State private var bottomResizeOffset: CGFloat = 0

    private let resizeHandleHeight: CGFloat = 6
    private let minimumDuration: TimeInterval = 15 * 60

    private var displayedInterval: DateInterval {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: displayDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(24 * 3600)
        let visibleStart = max(event.startDate, startOfDay)
        let visibleEnd = max(min(event.endDate, endOfDay), visibleStart)
        return DateInterval(start: visibleStart, end: visibleEnd)
    }

    var startOffset: CGFloat {
        let startOfDay = Calendar.current.startOfDay(for: displayDate)
        let secondsFromStartOfDay = displayedInterval.start.timeIntervalSince(startOfDay)
        return CGFloat(max(secondsFromStartOfDay, 0)) * (hourHeight / 3600)
    }

    var eventHeight: CGFloat {
        return max(CGFloat(displayedInterval.duration) * (hourHeight / 3600), 20)
    }

    /// Ширина события с учётом количества колонок
    var eventWidth: CGFloat {
        max(0, containerWidth * widthFraction - 2)
    }

    /// Горизонтальное смещение события
    var horizontalOffset: CGFloat {
        containerWidth * xFraction
    }

    /// Флаг любого взаимодействия
    private var isInteracting: Bool {
        isDragging || isResizingTop || isResizingBottom
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Основное тело события
            eventBody

            // Верхний хендлер для ресайза
            topResizeHandle

            // Нижний хендлер для ресайза
            bottomResizeHandle
        }
        .frame(width: eventWidth, height: max(1, eventHeight - topResizeOffset + bottomResizeOffset))
        .offset(x: horizontalOffset + dragOffsetX, y: startOffset + dragOffsetY + topResizeOffset)
        .padding(.horizontal, 1)
        .zIndex(isDragging ? 2000 : zIndexPriority) // Поднимаем перетаскиваемый элемент над другими
    }

    // MARK: - Event Body (Apple Calendar Style)

    /// Цвет текста - более тёмный оттенок цвета календаря
    private var textColor: Color {
        color.mix(with: .black, by: 0.4)
    }

    /// Цвет фона - светлый прозрачный, более насыщенный при выделении
    private var backgroundColor: Color {
        color.opacity(isSelected ? 0.95 : 0.25)
    }

    /// Цвет левой полоски - насыщенный цвет календаря
    private var accentBarColor: Color {
        color
    }

    private var eventBody: some View {
        HStack(spacing: 0) {
            // Яркая вертикальная полоска слева (как в Apple Calendar)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(accentBarColor)
                .frame(width: 3)

            // Контент события
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 10))
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .foregroundColor(textColor)

                // Время с иконкой часов (как в Apple Calendar)
                HStack(spacing: 2) {
                    Image(systemName: "clock")
                        .font(.system(size: 7))
                    Text(event.startDate.timeString())
                        .font(.system(size: 8))
                }
                .foregroundColor(textColor.opacity(0.8))
                .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(backgroundColor)
                .opacity(isInteracting ? 0.6 : 1.0)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(
                    accentBarColor.opacity(isSelected ? 0.5 : 0.3),
                    lineWidth: isSelected ? 1.5 : (isInteracting ? 1 : 0)
                )
        )
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onTapGesture {
            onEventTap()
        }
    }

    // MARK: - Resize Handles

    private var topResizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: resizeHandleHeight)
            .contentShape(Rectangle())
            .gesture(topResizeGesture)
            .resizeCursorIfAvailable()
    }

    private var bottomResizeHandle: some View {
        VStack {
            Spacer()
            Rectangle()
                .fill(Color.clear)
                .frame(height: resizeHandleHeight)
                .contentShape(Rectangle())
                .gesture(bottomResizeGesture)
                .resizeCursorIfAvailable()
        }
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .onChanged { value in
                isDragging = true
                dragOffsetX = value.translation.width
                dragOffsetY = value.translation.height
            }
            .onEnded { value in
                // Расчёт смещения по времени (вертикаль)
                let minutesDelta = Int(value.translation.height / (hourHeight / 60))
                let roundedMinutes = (minutesDelta / 15) * 15

                // Расчёт смещения по дням (горизонталь)
                let daysDelta = Int(round(value.translation.width / dayWidth))

                if roundedMinutes != 0 || daysDelta != 0 {
                    var updatedEvent = event

                    // Сначала смещаем по дням
                    var newStart = event.startDate
                    var newEnd = event.endDate

                    if daysDelta != 0 {
                        if let dayShiftedStart = Calendar.current.date(byAdding: .day, value: daysDelta, to: newStart),
                           let dayShiftedEnd = Calendar.current.date(byAdding: .day, value: daysDelta, to: newEnd) {
                            newStart = dayShiftedStart
                            newEnd = dayShiftedEnd
                        }
                    }

                    // Затем смещаем по времени
                    if roundedMinutes != 0 {
                        if let timeShiftedStart = Calendar.current.date(byAdding: .minute, value: roundedMinutes, to: newStart),
                           let timeShiftedEnd = Calendar.current.date(byAdding: .minute, value: roundedMinutes, to: newEnd) {
                            newStart = timeShiftedStart
                            newEnd = timeShiftedEnd
                        }
                    }

                    updatedEvent.startDate = newStart
                    updatedEvent.endDate = newEnd
                    onEventUpdate(updatedEvent)
                }

                dragOffsetX = 0
                dragOffsetY = 0
                isDragging = false
            }
    }

    private var topResizeGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                isResizingTop = true
                // Ограничиваем: вверх до начала дня, вниз до минимальной высоты
                let minOffset = -startOffset
                let maxOffset = eventHeight - 20
                topResizeOffset = min(max(value.translation.height, minOffset), maxOffset)
            }
            .onEnded { value in
                let minutesDelta = Int(value.translation.height / (hourHeight / 60))
                let roundedMinutes = (minutesDelta / 15) * 15

                if roundedMinutes != 0 {
                    var updatedEvent = event
                    if let newStart = Calendar.current.date(byAdding: .minute, value: roundedMinutes, to: event.startDate) {
                        if newStart < event.endDate.addingTimeInterval(-minimumDuration) {
                            updatedEvent.startDate = newStart
                            onEventUpdate(updatedEvent)
                        }
                    }
                }

                topResizeOffset = 0
                isResizingTop = false
            }
    }

    private var bottomResizeGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                isResizingBottom = true
                bottomResizeOffset = max(value.translation.height, -(eventHeight - 20))
            }
            .onEnded { value in
                let minutesDelta = Int(value.translation.height / (hourHeight / 60))
                let roundedMinutes = (minutesDelta / 15) * 15

                if roundedMinutes != 0 {
                    var updatedEvent = event
                    if let newEnd = Calendar.current.date(byAdding: .minute, value: roundedMinutes, to: event.endDate) {
                        if newEnd > event.startDate.addingTimeInterval(minimumDuration) {
                            updatedEvent.endDate = newEnd
                            onEventUpdate(updatedEvent)
                        }
                    }
                }

                bottomResizeOffset = 0
                isResizingBottom = false
            }
    }
}

struct MacWeekCurrentTimeIndicator: View {
    @State private var currentTime = Date()
    let hourHeight: CGFloat

    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: currentTime)
    }

    var body: some View {
        let hour = Calendar.current.component(.hour, from: currentTime)
        let minute = Calendar.current.component(.minute, from: currentTime)
        let offset = CGFloat(hour * 60 + minute) * (hourHeight / 60)

        GeometryReader { geometry in
            HStack(spacing: 0) {
                Text(timeString)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.red)
                    )
                    .offset(x: 8)

                Rectangle()
                    .fill(Color.red)
                    .frame(height: 2)
                    .offset(x: 12)
            }
            .offset(y: offset)
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }
}

#endif
