import XCTest
@testable import LawMaticCalendar

final class DateExtensionsTests: XCTestCase {
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
