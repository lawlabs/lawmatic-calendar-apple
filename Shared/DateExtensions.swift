import Foundation

extension Calendar {
    enum WeekdaySymbolStyle {
        /// «Пн», «Вт», …
        case short
        /// «П», «В», …
        case veryShort
    }

    /// Подписи дней недели в порядке колонок календарной сетки, т.е. начиная
    /// с `firstWeekday` текущей локали (в ru_RU — с понедельника).
    /// `getAllWeeksInMonth()` строит сетку от того же `firstWeekday`, поэтому
    /// подписи и колонки всегда совпадают.
    func orderedWeekdaySymbols(_ style: WeekdaySymbolStyle) -> [String] {
        // Интерфейс приложения русскоязычный, названия дней — тоже; а первый
        // день недели и часовой пояс берём из настроек региона пользователя.
        var localized = self
        localized.locale = Locale(identifier: "ru_RU")
        let symbols: [String]
        switch style {
        case .short:
            symbols = localized.shortStandaloneWeekdaySymbols
        case .veryShort:
            symbols = localized.veryShortStandaloneWeekdaySymbols
        }
        guard symbols.count == 7 else { return symbols }
        let firstIndex = max(0, min(6, firstWeekday - 1))
        return Array(symbols[firstIndex...] + symbols[..<firstIndex])
    }
}

extension Date {
    func startOfMonth() -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: self)
        return calendar.date(from: components) ?? self
    }

    func endOfMonth() -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth()) ?? self
    }

    func startOfWeek() -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return calendar.date(from: components) ?? self
    }

    func endOfWeek() -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: 6, to: startOfWeek()) ?? self
    }

    func startOfDay() -> Date {
        Calendar.current.startOfDay(for: self)
    }

    func endOfDay() -> Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfDay()) ?? self
    }

    func getAllDaysInMonth() -> [Date] {
        let calendar = Calendar.current
        let startDate = startOfMonth()
        guard let range = calendar.range(of: .day, in: .month, for: startDate) else {
            return [startDate]
        }

        return range.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: startDate)
        }
    }

    func getAllWeeksInMonth() -> [[Date]] {
        let calendar = Calendar.current
        let days = getAllDaysInMonth()

        var weeks: [[Date]] = []
        var currentWeek: [Date] = []

        if let firstDay = days.first {
            let weekday = calendar.component(.weekday, from: firstDay)
            let emptyDays = (weekday - calendar.firstWeekday + 7) % 7
            for _ in 0 ..< emptyDays {
                currentWeek.append(Date.distantPast)
            }
        }

        for day in days {
            currentWeek.append(day)

            if currentWeek.count == 7 {
                weeks.append(currentWeek)
                currentWeek = []
            }
        }

        if !currentWeek.isEmpty {
            while currentWeek.count < 7 {
                currentWeek.append(Date.distantPast)
            }
            weeks.append(currentWeek)
        }

        return weeks
    }

    func getDaysOfWeek() -> [Date] {
        let calendar = Calendar.current
        let weekStart = startOfWeek()

        return (0 ..< 7).compactMap { day in
            calendar.date(byAdding: .day, value: day, to: weekStart)
        }
    }

    private enum Formatters {
        static let monthYear: DateFormatter = {
            let df = DateFormatter()
            df.locale = Locale(identifier: "ru_RU")
            df.dateFormat = "LLLL yyyy"
            return df
        }()

        static let year: DateFormatter = {
            let df = DateFormatter()
            df.dateFormat = "yyyy"
            return df
        }()

        static let time: DateFormatter = {
            let df = DateFormatter()
            df.timeStyle = .short
            return df
        }()

        static let dayFull: DateFormatter = {
            let df = DateFormatter()
            df.locale = Locale(identifier: "ru_RU")
            df.dateFormat = "d MMMM, EEEE"
            return df
        }()

        static let dayShort: DateFormatter = {
            let df = DateFormatter()
            df.dateFormat = "d"
            return df
        }()

        static let weekdayFull: DateFormatter = {
            let df = DateFormatter()
            df.locale = Locale(identifier: "ru_RU")
            df.dateFormat = "EEEE"
            return df
        }()

        static let weekdayShort: DateFormatter = {
            let df = DateFormatter()
            df.locale = Locale(identifier: "ru_RU")
            df.dateFormat = "EEE"
            return df
        }()

        static let dayMonth: DateFormatter = {
            let df = DateFormatter()
            df.locale = Locale(identifier: "ru_RU")
            df.dateFormat = "d MMMM"
            return df
        }()
    }

    func monthYearString() -> String {
        Formatters.monthYear.string(from: self).capitalized
    }

    func yearString() -> String {
        Formatters.year.string(from: self)
    }

    func timeString() -> String {
        Formatters.time.string(from: self)
    }

    func dayString() -> String {
        Formatters.dayFull.string(from: self)
    }

    func shortDayString() -> String {
        Formatters.dayShort.string(from: self)
    }

    func weekdayString() -> String {
        Formatters.weekdayFull.string(from: self)
    }

    func shortWeekdayString() -> String {
        Formatters.weekdayShort.string(from: self).capitalized
    }

    func dayMonthString() -> String {
        Formatters.dayMonth.string(from: self)
    }

    func yearOnlyString() -> String {
        Formatters.year.string(from: self)
    }

    func weekdayLowerString() -> String {
        Formatters.weekdayFull.string(from: self).lowercased()
    }
}
