//
//  DayView.swift
//  CalendarTest45
//
//  Created by Sergey on 30.09.2025.
//

import Combine
import SwiftUI

struct DayView: View {
    @ObservedObject var viewModel: CalendarViewModel
    let hours = Array(0...23)
    let hourHeight: CGFloat = 60
    private let timeColumnWidth: CGFloat = 58
    @State private var creationDragStartY: CGFloat?

    private static let narrowWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEEEE"
        return formatter
    }()

    /// Вычисляет целевой час для начальной прокрутки (как в Apple Calendar)
    private var initialScrollHour: Int {
        if Calendar.current.isDateInToday(viewModel.selectedDate) {
            // Сегодня: прокручиваем к текущему часу минус 2 часа
            let currentHour = Calendar.current.component(.hour, from: Date())
            return max(0, currentHour - 2)
        } else {
            // Другой день: прокручиваем к 8:00 (начало рабочего дня)
            return 8
        }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                dayContextHeader
                allDayEventsSection

                ScrollViewReader { proxy in
                    ScrollView {
                        ZStack(alignment: .topLeading) {
                            timeGridBackground
                            creationOverlay(containerWidth: geometry.size.width - timeColumnWidth)
                            eventsOverlay(containerWidth: geometry.size.width - timeColumnWidth)
                            if Calendar.current.isDateInToday(viewModel.selectedDate) {
                                CurrentTimeIndicator(hourHeight: hourHeight)
                            }
                        }
                        .frame(minHeight: CGFloat(hours.count) * hourHeight)
                        .background(
                            VStack(spacing: 0) {
                                ForEach(hours, id: \.self) { hour in
                                    Color.clear
                                        .frame(height: hourHeight)
                                        .id("hour-\(hour)")
                                }
                            }
                        )
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo("hour-\(initialScrollHour)", anchor: .top)
                            }
                        }
                    }
                    .onChange(of: viewModel.selectedDate) { _, _ in
                        DispatchQueue.main.async {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo("hour-\(initialScrollHour)", anchor: .top)
                            }
                        }
                    }
                }
            }
        }
    }

    private var dayContextHeader: some View {
        VStack(spacing: 0) {
            weekStrip

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text(viewModel.selectedDate.dayMonthString() + " ")
                        .font(.title)
                        .fontWeight(.bold)
                    Text(viewModel.selectedDate.yearOnlyString() + " г.")
                        .font(.title)
                        .fontWeight(.regular)
                }

                Text(viewModel.selectedDate.weekdayLowerString())
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        //  .background(daycontextb)
    }

    private var weekStrip: some View {
        HStack(spacing: 0) {
            ForEach(viewModel.selectedDate.getDaysOfWeek(), id: \.self) { date in
                let isSelected = Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate)

                Button {
                    viewModel.selectedDate = date
                } label: {
                    VStack(spacing: 6) {
                        Text(weekdayLetter(for: date))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(isSelected ? .red : .secondary)

                        Text(date.shortDayString())
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(isSelected ? .white : .primary)
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(isSelected ? Color.red : Color.clear)
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func weekdayLetter(for date: Date) -> String {
        Self.narrowWeekdayFormatter.string(from: date).lowercased()
    }

    // MARK: - All Day Events Section

    @ViewBuilder
    private var allDayEventsSection: some View {
        let allDayEvents = viewModel.events(for: viewModel.selectedDate).filter { $0.isAllDay }
        if !allDayEvents.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Весь день")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(allDayEvents) { event in
                            AllDayEventRow(event: event, color: viewModel.color(for: event))
                                .onTapGesture {
                                    viewModel.selectEvent(event)
                                }
                        }
                    }
                }
                .frame(maxHeight: 100)
            }
            .padding(.vertical, 8)
            .background(
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.clearSelection()
                    }
            )

            Divider()
        }
    }

    // MARK: - Time Grid Background

    private var timeGridBackground: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(hours, id: \.self) { hour in
                    Text(String(format: "%02d:00", hour))
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(width: 50, height: hourHeight, alignment: .topTrailing)
                        .padding(.trailing, 8)
                }
            }

            VStack(spacing: 0) {
                ForEach(hours, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: hourHeight)
                        .overlay(
                            Divider()
                                .frame(height: 1),
                            alignment: .top
                        )
                }
            }
        }
    }

    private func creationOverlay(containerWidth: CGFloat) -> some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .frame(
                width: max(0, containerWidth),
                height: CGFloat(hours.count) * hourHeight
            )
            .offset(x: timeColumnWidth)
            .gesture(dragCreationGesture)
            .simultaneousGesture(doubleTapCreationGesture)
            .simultaneousGesture(backgroundSelectionClearGesture)
    }

    // MARK: - Events Overlay

    @ViewBuilder
    private func eventsOverlay(containerWidth: CGFloat) -> some View {
        let dayEvents = viewModel.events(for: viewModel.selectedDate).filter { !$0.isAllDay }
        let layoutInfos = EventLayoutCalculator.calculateLayout(
            for: dayEvents,
            on: viewModel.selectedDate,
            containerWidth: containerWidth,
            hourHeight: hourHeight
        )

        ZStack(alignment: .topLeading) {
            ForEach(layoutInfos, id: \.event.id) { layoutInfo in
                DraggableEventView(
                    event: layoutInfo.event,
                    displayDate: viewModel.selectedDate,
                    color: viewModel.color(for: layoutInfo.event).opacity(0.9),
                    hourHeight: hourHeight,
                    containerWidth: containerWidth,
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
        .padding(.leading, timeColumnWidth)
    }

    private func startDate(forVerticalLocation y: CGFloat) -> Date {
        let calendar = Calendar.current
        let clampedY = min(max(0, y), CGFloat(hours.count) * hourHeight)
        let rawMinutes = Int((clampedY / hourHeight) * 60)
        let roundedMinutes = min(23 * 60 + 45, ((rawMinutes + 7) / 15) * 15)
        let hour = roundedMinutes / 60
        let minute = roundedMinutes % 60

        return calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: viewModel.selectedDate
        ) ?? viewModel.selectedDate
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

// MARK: - Current Time Indicator

struct CurrentTimeIndicator: View {
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

// MARK: - All Day Event Row

struct AllDayEventRow: View {
    let event: CalendarEvent
    let color: Color

    /// Цвет текста - более тёмный оттенок цвета календаря
    private var textColor: Color {
        color.mix(with: .black, by: 0.4)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Яркая вертикальная полоска слева
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(textColor)

                if !event.location.isEmpty {
                    Text(event.location)
                        .font(.caption)
                        .foregroundColor(textColor.opacity(0.7))
                }
            }
            .padding(.horizontal, 8)

            Spacer()
        }
        .padding(.vertical, 8)
        .background(color.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal)
    }
}
