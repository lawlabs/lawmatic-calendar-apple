//
//  DraggableEventView.swift
//  CalendarTest45
//
//  Created by Sergey on 14.01.2026.
//

import SwiftUI

/// Режим взаимодействия с событием
enum EventInteractionMode {
    case none
    case dragging
    case resizingTop
    case resizingBottom
}

/// Компонент события с поддержкой перетаскивания и изменения размера
struct DraggableEventView: View {
    let event: CalendarEvent
    let displayDate: Date
    let color: Color
    let hourHeight: CGFloat
    let containerWidth: CGFloat
    let xFraction: CGFloat
    let widthFraction: CGFloat
    let zIndexPriority: Double
    let isSelected: Bool     // Выделено ли событие
    let onEventUpdate: (CalendarEvent) -> Void
    let onEventTap: () -> Void

    /// Инициализатор с параметрами наложений по умолчанию (одна колонка = полная ширина)
    init(
        event: CalendarEvent,
        displayDate: Date,
        color: Color,
        hourHeight: CGFloat,
        containerWidth: CGFloat,
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
        self.xFraction = xFraction
        self.widthFraction = widthFraction
        self.zIndexPriority = zIndexPriority ?? event.startDate.timeIntervalSince1970
        self.isSelected = isSelected
        self.onEventUpdate = onEventUpdate
        self.onEventTap = onEventTap
    }

    @State private var interactionMode: EventInteractionMode = .none
    @State private var dragOffset: CGFloat = 0
    @State private var topResizeOffset: CGFloat = 0
    @State private var bottomResizeOffset: CGFloat = 0

    private let resizeHandleHeight: CGFloat = 8
    private let minimumDuration: TimeInterval = 15 * 60 // 15 минут минимум

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

    /// Горизонтальное смещение события на основе номера колонки
    var horizontalOffset: CGFloat {
        containerWidth * xFraction
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Основное тело события
            eventBody

            // Хендлер верхней границы для ресайза
            topResizeHandle

            // Хендлер нижней границы для ресайза
            bottomResizeHandle
        }
        .frame(width: eventWidth, height: max(1, eventHeight - topResizeOffset + bottomResizeOffset))
        .offset(x: horizontalOffset, y: startOffset + dragOffset + topResizeOffset)
        .padding(.horizontal, 1)
        .zIndex(interactionMode == .dragging ? 2000 : zIndexPriority)
    }

    // MARK: - Event Body (Apple Calendar Style)

    /// Цвет текста - используем более тёмный оттенок цвета календаря
    private var textColor: Color {
        // Вычисляем более тёмный оттенок для текста
        color.opacity(1.0).mix(with: .black, by: 0.4)
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
            RoundedRectangle(cornerRadius: 2)
                .fill(accentBarColor)
                .frame(width: 4)

            // Контент события
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .foregroundColor(textColor)

                // Время с иконкой часов (как в Apple Calendar)
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                    Text("\(event.startDate.timeString()) — \(event.endDate.timeString())")
                        .font(.caption2)
                }
                .foregroundColor(textColor.opacity(0.8))
                .lineLimit(1)

                if !event.location.isEmpty {
                    Text(event.location)
                        .font(.caption2)
                        .foregroundColor(textColor.opacity(0.7))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColor)
                .opacity(interactionMode != .none ? 0.6 : 1.0)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    accentBarColor.opacity(isSelected ? 0.5 : 0.3),
                    lineWidth: isSelected ? 1.5 : (interactionMode != .none ? 2 : 0)
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
                interactionMode = .dragging
                dragOffset = value.translation.height
            }
            .onEnded { value in
                let minutesDelta = Int(value.translation.height / (hourHeight / 60))
                let roundedMinutes = (minutesDelta / 15) * 15 // Округляем до 15 минут

                if roundedMinutes != 0 {
                    var updatedEvent = event
                    if let newStart = Calendar.current.date(byAdding: .minute, value: roundedMinutes, to: event.startDate),
                       let newEnd = Calendar.current.date(byAdding: .minute, value: roundedMinutes, to: event.endDate) {
                        updatedEvent.startDate = newStart
                        updatedEvent.endDate = newEnd
                        onEventUpdate(updatedEvent)
                    }
                }

                dragOffset = 0
                interactionMode = .none
            }
    }

    private var topResizeGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                interactionMode = .resizingTop
                // Ограничиваем: вверх до начала дня (-startOffset), вниз до минимальной высоты
                let minOffset = -startOffset // Максимум вверх (отрицательное значение)
                let maxOffset = eventHeight - 20 // Максимум вниз (положительное значение)
                topResizeOffset = min(max(value.translation.height, minOffset), maxOffset)
            }
            .onEnded { value in
                let minutesDelta = Int(value.translation.height / (hourHeight / 60))
                let roundedMinutes = (minutesDelta / 15) * 15

                if roundedMinutes != 0 {
                    var updatedEvent = event
                    if let newStart = Calendar.current.date(byAdding: .minute, value: roundedMinutes, to: event.startDate) {
                        // Проверяем минимальную длительность
                        if newStart < event.endDate.addingTimeInterval(-minimumDuration) {
                            updatedEvent.startDate = newStart
                            onEventUpdate(updatedEvent)
                        }
                    }
                }

                topResizeOffset = 0
                interactionMode = .none
            }
    }

    private var bottomResizeGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                interactionMode = .resizingBottom
                // Ограничиваем, чтобы не сделать событие слишком коротким
                bottomResizeOffset = max(value.translation.height, -(eventHeight - 20))
            }
            .onEnded { value in
                let minutesDelta = Int(value.translation.height / (hourHeight / 60))
                let roundedMinutes = (minutesDelta / 15) * 15

                if roundedMinutes != 0 {
                    var updatedEvent = event
                    if let newEnd = Calendar.current.date(byAdding: .minute, value: roundedMinutes, to: event.endDate) {
                        // Проверяем минимальную длительность
                        if newEnd > event.startDate.addingTimeInterval(minimumDuration) {
                            updatedEvent.endDate = newEnd
                            onEventUpdate(updatedEvent)
                        }
                    }
                }

                bottomResizeOffset = 0
                interactionMode = .none
            }
    }
}
