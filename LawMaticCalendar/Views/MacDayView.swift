#if os(macOS)
import SwiftUI

struct MacDayView: View {
    var viewModel: CalendarViewModel
    let hours = Array(0...23)
    let hourHeight: CGFloat = 60
    private let timeColumnWidth: CGFloat = 58
    @State private var creationDragStartY: CGFloat?

    private var initialScrollHour: Int {
        if Calendar.current.isDateInToday(viewModel.selectedDate) {
            let currentHour = Calendar.current.component(.hour, from: Date())
            return max(0, currentHour - 2)
        } else {
            return 8
        }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 0) {
                        Text(viewModel.selectedDate.dayMonthString() + " ")
                            .font(.title)
                            .fontWeight(.bold)
                        Text(viewModel.selectedDate.yearOnlyString())
                            .font(.title)
                            .fontWeight(.regular)
                        Text(" г.")
                            .font(.title)
                            .fontWeight(.bold)
                    }

                    Text(viewModel.selectedDate.weekdayLowerString())
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 12)

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
                    // Смена даты не сбрасывает прокрутку: пользователь остаётся
                    // на том же часе (как в Apple Calendar).
                }
            }
        }
    }

    @ViewBuilder
    private var allDayEventsSection: some View {
        let allDayEvents = viewModel.events(for: viewModel.selectedDate).filter { $0.isAllDay }
        if !allDayEvents.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("весь день")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(allDayEvents) { event in
                            AllDayEventRow(
                                event: event,
                                color: viewModel.color(for: event),
                                isSelected: viewModel.selectedEventId == event.id
                            )
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

            TimeGridLines(hourHeight: hourHeight, hourCount: hours.count, columnCount: 1)
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
#endif
