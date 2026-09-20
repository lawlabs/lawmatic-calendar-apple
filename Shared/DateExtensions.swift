import Foundation

extension Date {
    func startOfWeek() -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return calendar.date(from: components) ?? self
    }

    func endOfWeek() -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: 6, to: startOfWeek()) ?? self
    }

    func endOfDay() -> Date {
        let calendar = Calendar.current
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return calendar.date(byAdding: components, to: calendar.startOfDay(for: self)) ?? self
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

    func timeString() -> String {
        Formatters.time.string(from: self)
    }

    func dayString() -> String {
        Formatters.dayFull.string(from: self)
    }

    func shortDayString() -> String {
        Formatters.dayShort.string(from: self)
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
