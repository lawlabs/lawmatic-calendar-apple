import Foundation
import SwiftUI

/// Демо-режим для показа и скриншотов: запуск с аргументами
/// `-demo 1 [-date 2026-09-23] [-mode week] [-colorScheme dark]`.
///
/// Данные — неделя демонстрационных событий в памяти, провайдеры выключены,
/// на диск ничего не пишется, настоящие календари пользователя не трогаются.
enum DemoMode {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "demo")
    }

    /// День, вокруг которого строится демо-неделя; по умолчанию сегодня.
    static var referenceDate: Date {
        guard let text = UserDefaults.standard.string(forKey: "date"),
              let date = try? Date(text, strategy: .iso8601.year().month().day())
        else { return Date() }
        return date
    }

    static var viewMode: ViewMode {
        switch UserDefaults.standard.string(forKey: "mode") {
        case "day": .day
        case "month": .month
        case "year": .year
        default: .week
        }
    }

    /// `-colorScheme dark|light` — закрепить тему независимо от системной.
    static var colorScheme: ColorScheme? {
        switch UserDefaults.standard.string(forKey: "colorScheme") {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }

    @MainActor
    static func makeViewModel() -> CalendarViewModel {
        let viewModel = CalendarViewModel(
            store: InMemoryCalendarStore(snapshot: CalendarSeedData.demoSnapshot(around: referenceDate)),
            providers: NoProviders()
        )
        viewModel.selectedDate = referenceDate
        viewModel.viewMode = viewMode
        return viewModel
    }

    /// Обычный или демо-VM в зависимости от аргументов запуска.
    @MainActor
    static func makeAppViewModel() -> CalendarViewModel {
        isEnabled ? makeViewModel() : CalendarViewModel()
    }
}

/// Пустой набор провайдеров: синхронизации нет.
@MainActor
private final class NoProviders: CalendarProviderResolving {
    var enabledProviders: [any CalendarProvider] { [] }
    func provider(_ id: ProviderID) -> (any CalendarProvider)? { nil }
}

extension CalendarSeedData {
    /// Та же неделя, что в демо-данных LawMatic Calendar для Windows, по-русски.
    static func demoSnapshot(around date: Date, calendar: Calendar = .current) -> CalendarStoreSnapshot {
        let calendars = [
            CalendarItem(name: "Работа", color: .purple, accountName: "Демо"),
            CalendarItem(name: "Встречи", color: .blue, accountName: "Демо"),
            CalendarItem(name: "Личное", color: .green, accountName: "Демо"),
            CalendarItem(name: "Важные даты", color: .orange, accountName: "Демо"),
        ]
        let work = calendars[0].id
        let meetings = calendars[1].id
        let personal = calendars[2].id
        let important = calendars[3].id

        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        let week = mondayFirst.date(from: mondayFirst.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))
            ?? calendar.startOfDay(for: date)

        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: week) ?? week
        }
        func at(_ offset: Int, _ hour: Double) -> Date {
            day(offset).addingTimeInterval(hour * 3600)
        }

        var events: [CalendarEvent] = []
        func add(_ offset: Int, _ hour: Double, _ duration: Double, _ title: String, _ calendarId: UUID, _ location: String = "", readOnly: Bool = false) {
            events.append(CalendarEvent(
                title: title,
                startDate: at(offset, hour),
                endDate: at(offset, hour + duration),
                location: location,
                calendarId: calendarId,
                isReadOnly: readOnly
            ))
        }
        func addAllDay(_ from: Int, _ to: Int, _ title: String, _ calendarId: UUID) {
            events.append(CalendarEvent(title: title, startDate: day(from), endDate: day(to), isAllDay: true, calendarId: calendarId))
        }

        add(0, 9, 1, "Планирование недели", work, "Офис")
        add(0, 11, 1.5, "Работа над проектом", work)
        add(0, 14, 1, "Командная встреча", meetings)
        add(1, 9.5, 1.5, "Подготовка документов", work)
        add(1, 12, 1, "Обед с Анной", personal)
        add(1, 14, 2, "Обсуждение проекта", meetings, "Переговорная 2")
        add(2, 9, 1, "Утренний фокус", work)
        add(2, 10.5, 1.5, "Консультация", meetings, "Онлайн")
        add(2, 11, 1.5, "Звонок партнёру", important)
        add(2, 15, 1.5, "Исследование и заметки", work)
        add(3, 9, 2, "Время для фокуса", work)
        add(3, 11, 1.5, "Судебное заседание", important, "Зал 412", readOnly: true)
        add(3, 12, 1, "Встреча с клиентом", meetings)
        add(3, 15, 1, "Прогулка", personal)
        add(4, 9.5, 1, "Обзор результатов", work)
        add(4, 11, 1.5, "Презентация проекта", meetings, "Онлайн")
        add(4, 14, 1, "Итоги недели", important)
        add(5, 10, 1.5, "Неспешный завтрак", personal)
        add(5, 14, 2, "Выставка", personal, "Музей современного искусства")
        add(6, 11, 1, "Время для себя", personal)
        addAllDay(1, 3, "Дизайн-дни", meetings)
        addAllDay(4, 5, "Дедлайн по проекту", important)

        // Соседние недели — чтобы месяц и год не были пустыми.
        for weekOffset in [-3, -2, -1, 1, 2, 3] {
            let base = weekOffset * 7
            add(base + 0, 9, 1, "Планирование недели", work, "Офис")
            add(base + 1, 12, 1, "Обед", personal)
            add(base + 2, 10.5, 1.5, "Консультация", meetings, "Онлайн")
            add(base + 3, 15, 1, "Прогулка", personal)
            add(base + 4, 11, 1.5, "Презентация", meetings)
            if weekOffset.isMultiple(of: 2) {
                addAllDay(base + 2, base + 3, "Срок подачи документов", important)
            }
        }

        return CalendarStoreSnapshot(calendars: calendars, events: events)
    }
}
