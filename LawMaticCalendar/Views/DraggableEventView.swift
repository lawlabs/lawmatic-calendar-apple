//
//  DraggableEventView.swift
//  CalendarTest45
//
//  Created by Sergey on 14.01.2026.
//

import SwiftUI

/// Вариант оформления блока события в сетке времени.
enum EventBlockStyle {
    /// Дневной вид: крупный шрифт, диапазон времени, место.
    case day
    /// Недельный вид: компактный шрифт, только время начала.
    case week

    fileprivate var metrics: Metrics {
        switch self {
        case .day:
            return Metrics(
                cornerRadius: 6, accentBarWidth: 4, contentSpacing: 2,
                horizontalPadding: 6, verticalPadding: 4,
                titleFont: .caption, timeFont: .caption2, clockFont: .system(size: 9),
                resizeHandleHeight: 8, showsEndTime: true, showsLocation: true
            )
        case .week:
            return Metrics(
                cornerRadius: 4, accentBarWidth: 3, contentSpacing: 1,
                horizontalPadding: 3, verticalPadding: 2,
                titleFont: .system(size: 10), timeFont: .system(size: 8), clockFont: .system(size: 7),
                resizeHandleHeight: 6, showsEndTime: false, showsLocation: false
            )
        }
    }

    fileprivate struct Metrics {
        let cornerRadius: CGFloat
        let accentBarWidth: CGFloat
        let contentSpacing: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let titleFont: Font
        let timeFont: Font
        let clockFont: Font
        let resizeHandleHeight: CGFloat
        let showsEndTime: Bool
        let showsLocation: Bool
    }
}

/// Блок события в сетке времени с перетаскиванием (по времени и, если задан
/// `dayWidth`, между днями) и изменением длительности за верхний/нижний край.
///
/// Во время взаимодействия положение и размер сразу привязываются к сетке
/// 15 минут, а рядом показывается подсказка с новым временем — то, что
/// пользователь видит, совпадает с тем, что будет сохранено.
struct DraggableEventView: View {
    let event: CalendarEvent
    let displayDate: Date
    let color: Color
    let hourHeight: CGFloat
    let containerWidth: CGFloat
    /// Ширина одной дневной колонки. `nil` — горизонтальное перетаскивание выключено.
    let dayWidth: CGFloat?
    let style: EventBlockStyle
    let xFraction: CGFloat
    let widthFraction: CGFloat
    let zIndexPriority: Double
    let isSelected: Bool
    let onEventUpdate: (CalendarEvent) -> Void
    let onEventTap: () -> Void

    init(
        event: CalendarEvent,
        displayDate: Date,
        color: Color,
        hourHeight: CGFloat,
        containerWidth: CGFloat,
        dayWidth: CGFloat? = nil,
        style: EventBlockStyle = .day,
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
        self.style = style
        self.xFraction = xFraction
        self.widthFraction = widthFraction
        self.zIndexPriority = zIndexPriority
            ?? EventLayoutCalculator.zIndexPriority(for: event, on: displayDate)
        self.isSelected = isSelected
        self.onEventUpdate = onEventUpdate
        self.onEventTap = onEventTap
    }

    @Environment(\.colorScheme) private var colorScheme

    private enum InteractionMode {
        case none, dragging, resizingTop, resizingBottom
    }

    @State private var interactionMode: InteractionMode = .none
    @State private var dragOffsetX: CGFloat = 0
    @State private var dragOffsetY: CGFloat = 0
    @State private var topResizeOffset: CGFloat = 0
    @State private var bottomResizeOffset: CGFloat = 0

    private static let minimumDuration: TimeInterval = 15 * 60
    private static let snapMinutes = 15
    /// zIndex перетаскиваемого блока. `zIndexPriority` лежит в пределах суток
    /// в секундах (< 86 400), поэтому это значение гарантированно выше.
    private static let interactingZIndex: Double = 1_000_000

    private var metrics: EventBlockStyle.Metrics { style.metrics }

    // MARK: - Геометрия

    private var displayedInterval: DateInterval {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: displayDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(24 * 3600)
        let visibleStart = max(event.startDate, startOfDay)
        let visibleEnd = max(min(event.endDate, endOfDay), visibleStart)
        return DateInterval(start: visibleStart, end: visibleEnd)
    }

    private var pointsPerMinute: CGFloat { hourHeight / 60 }
    private var snapStep: CGFloat { pointsPerMinute * CGFloat(Self.snapMinutes) }
    private var minimumHeight: CGFloat { max(20, pointsPerMinute * CGFloat(Self.minimumDuration / 60)) }

    var startOffset: CGFloat {
        let startOfDay = Calendar.current.startOfDay(for: displayDate)
        let secondsFromStartOfDay = displayedInterval.start.timeIntervalSince(startOfDay)
        return CGFloat(max(secondsFromStartOfDay, 0)) * (hourHeight / 3600)
    }

    var eventHeight: CGFloat {
        max(CGFloat(displayedInterval.duration) * (hourHeight / 3600), 20)
    }

    var eventWidth: CGFloat {
        max(0, containerWidth * widthFraction - 2)
    }

    var horizontalOffset: CGFloat {
        containerWidth * xFraction
    }

    private var isInteracting: Bool {
        interactionMode != .none
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            eventBody
            topResizeHandle
            bottomResizeHandle
        }
        .frame(width: eventWidth, height: max(1, eventHeight - topResizeOffset + bottomResizeOffset))
        .overlay(alignment: .topLeading) {
            if isInteracting {
                interactionTimeLabel
            }
        }
        .offset(x: horizontalOffset + dragOffsetX, y: startOffset + dragOffsetY + topResizeOffset)
        .padding(.horizontal, 1)
        .zIndex(isInteracting ? Self.interactingZIndex : zIndexPriority)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Оформление (в стиле Apple Calendar)

    private var textColor: Color {
        color.eventTextColor(isSelected: isSelected, colorScheme: colorScheme)
    }

    private var backgroundColor: Color {
        color.opacity(isSelected ? 0.95 : 0.25)
    }

    private var eventBody: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: metrics.accentBarWidth / 2)
                .fill(color)
                .frame(width: metrics.accentBarWidth)

            VStack(alignment: .leading, spacing: metrics.contentSpacing) {
                Text(event.title.isEmpty ? "Новое событие" : event.title)
                    .font(metrics.titleFont)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .foregroundColor(textColor)

                HStack(spacing: metrics.contentSpacing + 1) {
                    Image(systemName: "clock")
                        .font(metrics.clockFont)
                    Text(timeText)
                        .font(metrics.timeFont)
                }
                .foregroundColor(textColor.opacity(0.8))
                .lineLimit(1)

                if metrics.showsLocation, !event.location.isEmpty {
                    Text(event.location)
                        .font(metrics.timeFont)
                        .foregroundColor(textColor.opacity(0.7))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: metrics.cornerRadius)
                .fill(backgroundColor)
                .opacity(isInteracting ? 0.6 : 1.0)
        )
        .clipShape(RoundedRectangle(cornerRadius: metrics.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.cornerRadius)
                .stroke(
                    color.opacity(isSelected ? 0.5 : 0.3),
                    lineWidth: isSelected ? 1.5 : (isInteracting ? 1 : 0)
                )
        )
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onTapGesture {
            onEventTap()
        }
    }

    private var timeText: String {
        if metrics.showsEndTime {
            return "\(event.startDate.timeString()) — \(event.endDate.timeString())"
        }
        return event.startDate.timeString()
    }

    /// Подсказка с новым временем во время перетаскивания / ресайза.
    private var interactionTimeLabel: some View {
        let projected = projectedEvent()
        return Text("\(projected.startDate.timeString()) — \(projected.endDate.timeString())")
            .font(.system(size: 10, weight: .semibold))
            .monospacedDigit()
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor))
            .fixedSize()
            .offset(x: 2, y: -18)
            .allowsHitTesting(false)
    }

    private var accessibilityDescription: String {
        let title = event.title.isEmpty ? "Новое событие" : event.title
        return "\(title), \(event.startDate.timeString()) — \(event.endDate.timeString())"
    }

    // MARK: - Ручки ресайза

    private var topResizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: metrics.resizeHandleHeight)
            .contentShape(Rectangle())
            .gesture(topResizeGesture)
            .resizeCursorIfAvailable()
    }

    private var bottomResizeHandle: some View {
        VStack {
            Spacer()
            Rectangle()
                .fill(Color.clear)
                .frame(height: metrics.resizeHandleHeight)
                .contentShape(Rectangle())
                .gesture(bottomResizeGesture)
                .resizeCursorIfAvailable()
        }
    }

    // MARK: - Расчёт нового времени

    private func minutes(fromPoints points: CGFloat) -> Int {
        Int((points / pointsPerMinute).rounded())
    }

    private func snapped(_ points: CGFloat) -> CGFloat {
        (points / snapStep).rounded() * snapStep
    }

    private func snappedDayOffset(_ points: CGFloat) -> CGFloat {
        guard let dayWidth, dayWidth > 0 else { return 0 }
        return (points / dayWidth).rounded() * dayWidth
    }

    private var daysDelta: Int {
        guard let dayWidth, dayWidth > 0 else { return 0 }
        return Int((dragOffsetX / dayWidth).rounded())
    }

    /// Событие с учётом текущих смещений — то, что будет сохранено при отпускании.
    private func projectedEvent() -> CalendarEvent {
        let calendar = Calendar.current
        var updated = event

        switch interactionMode {
        case .dragging:
            var newStart = event.startDate
            var newEnd = event.endDate
            if daysDelta != 0,
               let shiftedStart = calendar.date(byAdding: .day, value: daysDelta, to: newStart),
               let shiftedEnd = calendar.date(byAdding: .day, value: daysDelta, to: newEnd) {
                newStart = shiftedStart
                newEnd = shiftedEnd
            }
            let minutesDelta = minutes(fromPoints: dragOffsetY)
            if minutesDelta != 0,
               let shiftedStart = calendar.date(byAdding: .minute, value: minutesDelta, to: newStart),
               let shiftedEnd = calendar.date(byAdding: .minute, value: minutesDelta, to: newEnd) {
                newStart = shiftedStart
                newEnd = shiftedEnd
            }
            updated.startDate = newStart
            updated.endDate = newEnd

        case .resizingTop:
            let minutesDelta = minutes(fromPoints: topResizeOffset)
            if minutesDelta != 0,
               let newStart = calendar.date(byAdding: .minute, value: minutesDelta, to: event.startDate),
               newStart <= event.endDate.addingTimeInterval(-Self.minimumDuration) {
                updated.startDate = newStart
            }

        case .resizingBottom:
            let minutesDelta = minutes(fromPoints: bottomResizeOffset)
            if minutesDelta != 0,
               let newEnd = calendar.date(byAdding: .minute, value: minutesDelta, to: event.endDate),
               newEnd >= event.startDate.addingTimeInterval(Self.minimumDuration) {
                updated.endDate = newEnd
            }

        case .none:
            break
        }

        return updated
    }

    private func commitInteraction() {
        let updated = projectedEvent()
        if updated.startDate != event.startDate || updated.endDate != event.endDate {
            onEventUpdate(updated)
        }
        dragOffsetX = 0
        dragOffsetY = 0
        topResizeOffset = 0
        bottomResizeOffset = 0
        interactionMode = .none
    }

    // MARK: - Жесты

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .onChanged { value in
                interactionMode = .dragging
                dragOffsetX = snappedDayOffset(value.translation.width)
                dragOffsetY = snapped(value.translation.height)
            }
            .onEnded { _ in
                commitInteraction()
            }
    }

    private var topResizeGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                interactionMode = .resizingTop
                let minOffset = -startOffset
                let maxOffset = eventHeight - minimumHeight
                topResizeOffset = min(max(snapped(value.translation.height), minOffset), maxOffset)
            }
            .onEnded { _ in
                commitInteraction()
            }
    }

    private var bottomResizeGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                interactionMode = .resizingBottom
                bottomResizeOffset = max(snapped(value.translation.height), -(eventHeight - minimumHeight))
            }
            .onEnded { _ in
                commitInteraction()
            }
    }
}
