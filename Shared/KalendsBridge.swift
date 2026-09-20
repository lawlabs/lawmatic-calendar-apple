import Foundation
import Kalends
import SwiftUI

/// То, что видит Kalends: событие без полей синхронизации, с уже
/// вычисленным цветом календаря и правом редактирования. По `id` VM находит
/// свой `CalendarEvent` в колбэках.
struct CalendarDisplayEvent: KalendsEvent {
    let id: UUID
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let color: Color
    let isReadOnly: Bool
    let subtitle: String?

    init(_ event: CalendarEvent, color: Color, isReadOnly: Bool) {
        id = event.id
        title = event.title
        startDate = event.startDate
        endDate = event.endDate
        isAllDay = event.isAllDay
        self.color = color
        self.isReadOnly = isReadOnly
        subtitle = event.location.isEmpty ? nil : event.location
    }
}

extension ViewMode {
    var kalendsMode: KalendsMode {
        switch self {
        case .day: .day
        case .week: .week
        case .month: .month
        case .year: .year
        }
    }
}

extension CalendarViewModel: KalendsDataSource {
    func events(on day: Date) -> [CalendarDisplayEvent] {
        repository.events(for: day).map { event in
            CalendarDisplayEvent(event, color: repository.color(for: event), isReadOnly: !canEdit(event))
        }
    }

    // `hasEvents(on:)` уже есть у VM и подходит под протокол.

    /// Колбэки календарных view: каждое действие пользователя в сетке
    /// превращается в операцию VM, как раньше делали сами view.
    var kalendsActions: KalendsActions<CalendarDisplayEvent> {
        KalendsActions(
            selectEvent: { [weak self] displayed in
                guard let self, let event = repository.event(withID: displayed.id) else { return }
                selectEvent(event)
            },
            clearSelection: { [weak self] in
                self?.clearSelection()
            },
            rescheduleEvent: { [weak self] displayed, interval in
                guard let self, var event = repository.event(withID: displayed.id) else { return }
                event.startDate = interval.start
                event.endDate = interval.end
                updateEvent(event)
            },
            createEvent: { [weak self] start in
                guard let self else { return }
                createNewEvent(at: start, duration: defaultDurationForQuickCreate(at: start))
            },
            updateDraft: { [weak self] interval in
                self?.updatePendingNewEvent(startDate: interval.start, endDate: interval.end)
            },
            openDay: { [weak self] date in
                self?.selectedDate = date
                self?.viewMode = .day
            }
        )
    }
}

/// Календарь приложения в текущем режиме, подключённый к VM.
struct CalendarWorkspaceView: View {
    @Bindable var viewModel: CalendarViewModel

    var body: some View {
        KalendsView(
            mode: viewModel.viewMode.kalendsMode,
            source: viewModel,
            selectedDate: $viewModel.selectedDate,
            selectedEventID: viewModel.selectedEventId,
            actions: viewModel.kalendsActions
        )
    }
}
