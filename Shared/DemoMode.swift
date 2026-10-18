import Foundation
import Kalends
import SwiftUI

/// Демо-режим для показа и скриншотов: запуск с аргументами
/// `-demo 1 [-date 2026-09-23] [-mode week] [-colorScheme dark]`.
///
/// Данные — неделя демонстрационных событий в памяти, провайдеры не
/// создаются, на диск ничего не пишется, настоящие календари пользователя и
/// связка ключей не трогаются.
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
        let snapshot = CalendarSeedData.demoSnapshot(
            around: referenceDate,
            busyDay: UserDefaults.standard.bool(forKey: "demoBusyDay")
        )
        let viewModel = CalendarViewModel(
            store: InMemoryCalendarStore(snapshot: snapshot),
            providers: NoProviders()
        )
        viewModel.selectedDate = referenceDate
        viewModel.viewMode = viewMode
        if UserDefaults.standard.bool(forKey: "demoDayKinds") {
            for (date, info) in CalendarSeedData.demoDayInfo(around: referenceDate) {
                viewModel.setDayInfo(info, for: date)
            }
        }
        return viewModel
    }

    /// Приложение запущено как хост юнит-тестов (`xcodebuild test`). Тесты
    /// создают свои модели с заглушками, а окну приложения незачем открывать
    /// настоящие календари, связку ключей и синхронизацию.
    static var isTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Можно ли подключать настоящие аккаунты: провайдеры, Keychain,
    /// синхронизацию. Нельзя в демо-режиме и при запуске для тестов.
    static var usesUserAccounts: Bool {
        !isEnabled && !isTestHost
    }

    /// Обычный, демо- или пустой VM в зависимости от того, как запущено приложение.
    @MainActor
    static func makeAppViewModel() -> CalendarViewModel {
        if isEnabled {
            return makeViewModel()
        }
        if isTestHost {
            return CalendarViewModel(store: InMemoryCalendarStore(), providers: NoProviders())
        }
        return CalendarViewModel(display: .persistent())
    }
}

/// Вместо настроек аккаунтов в демо-режиме и при запуске для тестов:
/// настоящие провайдеры не создаются, поэтому Keychain не читается.
struct AccountsUnavailableView: View {
    var body: some View {
        ContentUnavailableView(
            "Аккаунты не подключены",
            systemImage: "person.crop.circle.badge.xmark",
            description: Text("В демо-режиме календари и аккаунты пользователя не используются.")
        )
        .frame(minWidth: 420, minHeight: 260)
    }
}

/// Пустой набор провайдеров: синхронизации нет.
@MainActor
private final class NoProviders: CalendarProviderResolving {
    var enabledProviders: [any CalendarProvider] { [] }
    func provider(_ id: ProviderID) -> (any CalendarProvider)? { nil }
}

extension CalendarSeedData {
    /// Вымышленные статусы для проверки оформления, только с `-demoDayKinds 1`.
    /// Это не производственный календарь и не сведения о настоящих праздниках.
    static func demoDayInfo(around date: Date, calendar: Calendar = .current) -> [Date: KalendsDayInfo] {
        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        let week = mondayFirst.date(from: mondayFirst.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))
            ?? calendar.startOfDay(for: date)
        let examples: [(Int, KalendsDayInfo)] = [
            (0, KalendsDayInfo(kind: .holiday, description: "Демо: праздничный день")),
            (1, KalendsDayInfo(kind: .transferredDayOff, description: "Демо: перенесённый выходной")),
            (3, KalendsDayInfo(isShortened: true, description: "Демо: сокращённый рабочий день")),
            (5, KalendsDayInfo(kind: .transferredWorking, isShortened: true,
                               description: "Демо: рабочая суббота по переносу, сокращённый день")),
        ]
        return Dictionary(uniqueKeysWithValues: examples.compactMap { offset, info in
            calendar.date(byAdding: .day, value: offset, to: week).map { ($0, info) }
        })
    }

    /// Та же неделя, что в демо-данных LawMatic Calendar для Windows, по-русски.
    ///
    /// `busyDay` (аргумент `-demoBusyDay 1`) заменяет события дня `date`
    /// плотным днём для проверки раскладки пересечений: события в одно
    /// время, вложенные одно в другое, пять в одной строке.
    static func demoSnapshot(around date: Date, busyDay: Bool = false, calendar: Calendar = .current) -> CalendarStoreSnapshot {
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

        if busyDay {
            let offset = calendar.dateComponents([.day], from: week, to: calendar.startOfDay(for: date)).day ?? 0
            events.removeAll { !$0.isAllDay && calendar.isDate($0.startDate, inSameDayAs: date) }
            add(offset, 8.25, 1, "Заседание в районном суде", important, "Зал 5")
            add(offset, 9, 1, "Отправить курьера в суд с документами", work)
            add(offset, 10, 1, "Клиент приедет в офис — уточнить время приезда", meetings)
            add(offset, 10, 1, "Заявление на выдачу исполнительных листов, жалобу подать в срок", work)
            add(offset, 11, 1, "Актуализировать таблицу по делам", work)
            add(offset, 11.5, 1, "Запросить документы по делу 115", important)
            add(offset, 11.5, 1, "Клиент в офисе в 11:30", meetings)
            add(offset, 12, 1, "Арбитражный суд: в 12:30 иск ООО «Вектор» к ООО «Альфа»", important, readOnly: true)
            add(offset, 12, 1, "Беседа в судебном участке перенесена", meetings)
            add(offset, 12, 1, "Раздать дела на время отпуска", work)
            add(offset, 13, 1, "Подготовить документы за ноябрь и отправить сторонам", important)
            add(offset, 13.5, 1, "Забрать детей", personal)
            add(offset, 14, 1, "Дорога домой", personal)
            add(offset, 14, 1, "Районный суд", important)
            add(offset, 15, 1, "Поправить уведомление и устав", work)
            add(offset, 15, 1, "Отправить претензию поставщику", work)
            add(offset, 15, 1, "Созвон с экспертом", meetings)
            add(offset, 15, 1, "Обжалуем? Последний день срока — 29.10", important)
            add(offset, 15.25, 1, "Назначили заседание?", meetings)
            add(offset, 18.5, 1, "Согласовать мировое соглашение", important)
            add(offset, 19.25, 1, "Забрать велосипед из ремонта", personal)
        }

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
