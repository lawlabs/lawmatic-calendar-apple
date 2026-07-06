import Foundation

enum CalendarSeedData {
    static func defaultCalendars() -> [CalendarItem] {
        [
            CalendarItem(name: "Личный", color: .blue, accountName: "Локально"),
            CalendarItem(name: "Работа", color: .red, accountName: "Локально"),
            CalendarItem(name: "Семья", color: .green, accountName: "Локально"),
            CalendarItem(name: "Спорт", color: .orange, accountName: "Локально"),
            CalendarItem(name: "Праздники РФ", color: .purple, accountName: "Локально"),
        ]
    }

    static func previewSnapshot(baseDate: Date = Date()) -> CalendarStoreSnapshot {
        let calendars = defaultCalendars()
        let calendar = Calendar.current

        guard calendars.count >= 4 else {
            return CalendarStoreSnapshot(calendars: calendars, events: [])
        }

        let personalId = calendars[0].id
        let workId = calendars[1].id
        let familyId = calendars[2].id
        let sportId = calendars[3].id

        var events: [CalendarEvent] = [
            CalendarEvent(
                title: "Встреча с командой",
                startDate: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: baseDate) ?? baseDate,
                endDate: calendar.date(bySettingHour: 11, minute: 30, second: 0, of: baseDate) ?? baseDate.addingTimeInterval(90 * 60),
                notes: "Обсуждение планов на неделю",
                location: "Офис",
                calendarId: workId
            ),
            CalendarEvent(
                title: "Обед",
                startDate: calendar.date(bySettingHour: 13, minute: 0, second: 0, of: baseDate) ?? baseDate,
                endDate: calendar.date(bySettingHour: 14, minute: 0, second: 0, of: baseDate) ?? baseDate.addingTimeInterval(60 * 60),
                location: "Кафе",
                calendarId: personalId
            ),
            CalendarEvent(
                title: "Презентация проекта",
                startDate: calendar.date(bySettingHour: 15, minute: 0, second: 0, of: baseDate) ?? baseDate,
                endDate: calendar.date(bySettingHour: 17, minute: 0, second: 0, of: baseDate) ?? baseDate.addingTimeInterval(2 * 60 * 60),
                notes: "Важная презентация для клиента",
                location: "Конференц-зал",
                calendarId: workId
            ),
            CalendarEvent(
                title: "Звонок с заказчиком",
                startDate: calendar.date(bySettingHour: 10, minute: 30, second: 0, of: baseDate) ?? baseDate,
                endDate: calendar.date(bySettingHour: 11, minute: 0, second: 0, of: baseDate) ?? baseDate.addingTimeInterval(30 * 60),
                location: "Zoom",
                calendarId: personalId
            ),
            CalendarEvent(
                title: "Созвон с партнёрами",
                startDate: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: baseDate) ?? baseDate,
                endDate: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: baseDate) ?? baseDate.addingTimeInterval(2 * 60 * 60),
                calendarId: familyId
            ),
            CalendarEvent(
                title: "Совещание #1",
                startDate: calendar.date(bySettingHour: 14, minute: 0, second: 0, of: baseDate) ?? baseDate,
                endDate: calendar.date(bySettingHour: 15, minute: 0, second: 0, of: baseDate) ?? baseDate.addingTimeInterval(60 * 60),
                calendarId: workId
            ),
            CalendarEvent(
                title: "Совещание #2",
                startDate: calendar.date(bySettingHour: 14, minute: 0, second: 0, of: baseDate) ?? baseDate,
                endDate: calendar.date(bySettingHour: 14, minute: 45, second: 0, of: baseDate) ?? baseDate.addingTimeInterval(45 * 60),
                calendarId: personalId
            ),
            CalendarEvent(
                title: "Короткий звонок",
                startDate: calendar.date(bySettingHour: 14, minute: 15, second: 0, of: baseDate) ?? baseDate,
                endDate: calendar.date(bySettingHour: 14, minute: 30, second: 0, of: baseDate) ?? baseDate.addingTimeInterval(30 * 60),
                calendarId: sportId
            ),
        ]

        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: baseDate) {
            events.append(
                CalendarEvent(
                    title: "Спортзал",
                    startDate: calendar.date(bySettingHour: 7, minute: 0, second: 0, of: tomorrow) ?? tomorrow,
                    endDate: calendar.date(bySettingHour: 8, minute: 30, second: 0, of: tomorrow) ?? tomorrow.addingTimeInterval(90 * 60),
                    location: "Фитнес-центр",
                    calendarId: sportId
                )
            )

            events.append(
                CalendarEvent(
                    title: "Вебинар",
                    startDate: calendar.date(bySettingHour: 16, minute: 0, second: 0, of: tomorrow) ?? tomorrow,
                    endDate: calendar.date(bySettingHour: 18, minute: 0, second: 0, of: tomorrow) ?? tomorrow.addingTimeInterval(2 * 60 * 60),
                    calendarId: workId
                )
            )
        }

        if let nextWeek = calendar.date(byAdding: .day, value: 7, to: baseDate) {
            let allDayDate = calendar.startOfDay(for: nextWeek)
            events.append(
                CalendarEvent(
                    title: "День рождения",
                    startDate: allDayDate,
                    endDate: allDayDate,
                    isAllDay: true,
                    calendarId: familyId
                )
            )
        }

        return CalendarStoreSnapshot(calendars: calendars, events: events)
    }
}
