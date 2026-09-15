import XCTest
@testable import LawMaticCalendar

final class DateExtensionsTests: XCTestCase {
    func testGetAllWeeksInMonthReturnsFullWeeks() {
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 1
        let date = Calendar.current.date(from: components) ?? Date()

        let weeks = date.getAllWeeksInMonth()

        XCTAssertFalse(weeks.isEmpty)
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
    }

    func testStartAndEndOfWeekContainOriginalDate() {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 18
        let date = Calendar.current.date(from: components) ?? Date()

        let startOfWeek = date.startOfWeek()
        let endOfWeek = date.endOfWeek()

        XCTAssertLessThanOrEqual(startOfWeek, date)
        XCTAssertGreaterThanOrEqual(endOfWeek, date)
    }
}

final class CalendarWeekdaySymbolsTests: XCTestCase {
    /// Подписи всегда русские (как весь интерфейс), а порядок — от
    /// `firstWeekday` текущего региона.
    private var russianSymbols: [String] {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "ru_RU")
        return calendar.shortStandaloneWeekdaySymbols
    }

    func testOrderedWeekdaySymbolsStartWithFirstWeekday() {
        let calendar = Calendar.current
        let ordered = calendar.orderedWeekdaySymbols(.short)

        XCTAssertEqual(ordered.count, 7)
        XCTAssertEqual(ordered.first, russianSymbols[calendar.firstWeekday - 1])
        XCTAssertEqual(Set(ordered), Set(russianSymbols))
    }

    func testOrderedWeekdaySymbolsMatchGridColumns() throws {
        let calendar = Calendar.current
        let firstWeek = try XCTUnwrap(Date().getAllWeeksInMonth().first)
        let firstRealDay = try XCTUnwrap(firstWeek.first(where: { $0 != Date.distantPast }))
        let column = try XCTUnwrap(firstWeek.firstIndex(of: firstRealDay))
        let weekdayIndex = calendar.component(.weekday, from: firstRealDay) - 1

        XCTAssertEqual(
            calendar.orderedWeekdaySymbols(.short)[column],
            russianSymbols[weekdayIndex]
        )
    }

    func testOrderedWeekdaySymbolsRespectMondayFirstRegion() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2

        XCTAssertEqual(calendar.orderedWeekdaySymbols(.short), ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"])
    }

    func testOrderedWeekdaySymbolsRespectSundayFirstRegion() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1

        XCTAssertEqual(calendar.orderedWeekdaySymbols(.veryShort), ["В", "П", "В", "С", "Ч", "П", "С"])
    }
}
