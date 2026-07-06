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
