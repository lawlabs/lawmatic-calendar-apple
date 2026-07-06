import XCTest
@testable import LawMaticCalendar

final class EventLayoutCalculatorTests: XCTestCase {
    private let containerWidth: CGFloat = 300
    private let hourHeight: CGFloat = 60

    func testOverlappingTitleBandsSplitEventsHorizontally() {
        let day = makeDay()
        let firstEvent = makeEvent("One", day: day, startHour: 10, startMinute: 0, endHour: 11, endMinute: 0)
        let secondEvent = makeEvent("Two", day: day, startHour: 10, startMinute: 10, endHour: 10, endMinute: 50)

        let layout = calculateLayout(for: [firstEvent, secondEvent], day: day)
        let firstLayout = layoutInfo(for: firstEvent, in: layout)
        let secondLayout = layoutInfo(for: secondEvent, in: layout)

        XCTAssertEqual(layout.count, 2)
        XCTAssertNotNil(firstLayout)
        XCTAssertNotNil(secondLayout)
        XCTAssertEqual(firstLayout?.xFraction ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(firstLayout?.overlapDepth, 0)
        XCTAssertEqual(secondLayout?.overlapDepth, 1)
        XCTAssertGreaterThan(firstLayout?.widthFraction ?? 0, 0.55)
        XCTAssertLessThan(firstLayout?.widthFraction ?? 1, 0.62)
        XCTAssertGreaterThan(secondLayout?.xFraction ?? 0, 0.38)
        XCTAssertLessThan(secondLayout?.xFraction ?? 1, 0.44)
        XCTAssertGreaterThan(secondLayout?.widthFraction ?? 0, 0.55)
        XCTAssertLessThan(secondLayout?.widthFraction ?? 1, 0.62)
    }

    func testSeparatedEventsReuseFullWidth() {
        let day = makeDay()
        let firstEvent = makeEvent("Morning", day: day, startHour: 9, startMinute: 0, endHour: 10, endMinute: 0)
        let secondEvent = makeEvent("Afternoon", day: day, startHour: 11, startMinute: 0, endHour: 12, endMinute: 0)

        let layout = calculateLayout(for: [firstEvent, secondEvent], day: day)

        XCTAssertEqual(layout.count, 2)
        XCTAssertTrue(layout.allSatisfy { abs($0.xFraction) < 0.001 })
        XCTAssertTrue(layout.allSatisfy { $0.widthFraction > 0.99 })
    }

    func testBodyOverlapKeepsLongEventWide() {
        let day = makeDay()
        let longEvent = makeEvent("Long", day: day, startHour: 9, startMinute: 0, endHour: 12, endMinute: 0)
        let shortEvent = makeEvent("Short", day: day, startHour: 10, startMinute: 0, endHour: 11, endMinute: 0)

        let layout = calculateLayout(for: [longEvent, shortEvent], day: day)
        let longLayout = layoutInfo(for: longEvent, in: layout)
        let shortLayout = layoutInfo(for: shortEvent, in: layout)

        XCTAssertEqual(layout.count, 2)
        XCTAssertNotNil(longLayout)
        XCTAssertNotNil(shortLayout)
        XCTAssertEqual(longLayout?.xFraction ?? -1, 0, accuracy: 0.001)
        XCTAssertGreaterThan(shortLayout?.xFraction ?? 0, 0.03)
        XCTAssertGreaterThan(longLayout?.widthFraction ?? 0, 0.95)
        XCTAssertGreaterThan(shortLayout?.widthFraction ?? 0, 0.88)
        XCTAssertLessThan(shortLayout?.widthFraction ?? 1, 0.95)
    }

    func testThreeStackAssignsIncreasingDepthAndStaggeredOffsets() {
        let day = makeDay()
        let firstEvent = makeEvent("A", day: day, startHour: 12, startMinute: 0, endHour: 14, endMinute: 0)
        let secondEvent = makeEvent("B", day: day, startHour: 12, startMinute: 5, endHour: 13, endMinute: 0)
        let thirdEvent = makeEvent("C", day: day, startHour: 12, startMinute: 10, endHour: 13, endMinute: 15)

        let layout = calculateLayout(for: [firstEvent, secondEvent, thirdEvent], day: day)
        let firstLayout = layoutInfo(for: firstEvent, in: layout)
        let secondLayout = layoutInfo(for: secondEvent, in: layout)
        let thirdLayout = layoutInfo(for: thirdEvent, in: layout)

        XCTAssertEqual(layout.count, 3)
        XCTAssertEqual(firstLayout?.overlapDepth, 0)
        XCTAssertEqual(secondLayout?.overlapDepth, 1)
        XCTAssertEqual(thirdLayout?.overlapDepth, 2)
        XCTAssertEqual(firstLayout?.overlapStackCount, 3)
        XCTAssertEqual(secondLayout?.overlapStackCount, 3)
        XCTAssertEqual(thirdLayout?.overlapStackCount, 3)
        XCTAssertLessThan(firstLayout?.xFraction ?? 1, secondLayout?.xFraction ?? 0)
        XCTAssertLessThan(secondLayout?.xFraction ?? 1, thirdLayout?.xFraction ?? 0)
        XCTAssertGreaterThan(firstLayout?.widthFraction ?? 0, 0.45)
        XCTAssertGreaterThan(secondLayout?.widthFraction ?? 0, 0.45)
        XCTAssertGreaterThan(thirdLayout?.widthFraction ?? 0, 0.45)
    }

    func testLaterLongBodyOverlapGetsRevealGap() {
        let day = makeDay()
        let firstEvent = makeEvent("Primary", day: day, startHour: 12, startMinute: 0, endHour: 13, endMinute: 45)
        let secondEvent = makeEvent("Secondary", day: day, startHour: 12, startMinute: 45, endHour: 15, endMinute: 0)

        let layout = calculateLayout(for: [firstEvent, secondEvent], day: day)
        let firstLayout = layoutInfo(for: firstEvent, in: layout)
        let secondLayout = layoutInfo(for: secondEvent, in: layout)

        XCTAssertEqual(layout.count, 2)
        XCTAssertEqual(firstLayout?.xFraction ?? -1, 0, accuracy: 0.001)
        XCTAssertGreaterThan(secondLayout?.xFraction ?? 0, 0.03)
        XCTAssertGreaterThan(firstLayout?.widthFraction ?? 0, 0.95)
        XCTAssertGreaterThan(secondLayout?.widthFraction ?? 0, 0.88)
        XCTAssertLessThan(secondLayout?.widthFraction ?? 1, 0.95)
    }

    func testLaterEventReturnsToFullWidthAfterEarlierOverlapCluster() {
        let day = makeDay()
        let firstEvent = makeEvent("First", day: day, startHour: 9, startMinute: 0, endHour: 9, endMinute: 45)
        let secondEvent = makeEvent("Second", day: day, startHour: 9, startMinute: 5, endHour: 9, endMinute: 25)
        let thirdEvent = makeEvent("Third", day: day, startHour: 10, startMinute: 0, endHour: 10, endMinute: 45)

        let layout = calculateLayout(for: [firstEvent, secondEvent, thirdEvent], day: day)
        let thirdLayout = layoutInfo(for: thirdEvent, in: layout)

        XCTAssertEqual(layout.count, 3)
        XCTAssertNotNil(thirdLayout)
        XCTAssertEqual(thirdLayout?.xFraction ?? -1, 0, accuracy: 0.001)
        XCTAssertGreaterThan(thirdLayout?.widthFraction ?? 0, 0.95)
    }

    func testEventsTouchingBoundariesDoNotOverlap() {
        let day = makeDay()
        let firstEvent = makeEvent("First", day: day, startHour: 10, startMinute: 0, endHour: 10, endMinute: 30)
        let secondEvent = makeEvent("Second", day: day, startHour: 10, startMinute: 30, endHour: 11, endMinute: 0)

        let layout = calculateLayout(for: [firstEvent, secondEvent], day: day)

        XCTAssertEqual(layout.count, 2)
        XCTAssertTrue(layout.allSatisfy { abs($0.xFraction) < 0.001 })
        XCTAssertTrue(layout.allSatisfy { $0.widthFraction > 0.99 })
    }

    private func makeDay() -> Date {
        Calendar.current.startOfDay(for: Date())
    }

    private func makeEvent(
        _ title: String,
        day: Date,
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int
    ) -> CalendarEvent {
        let calendar = Calendar.current
        return CalendarEvent(
            title: title,
            startDate: calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: day) ?? day,
            endDate: calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: day) ?? day,
            calendarId: UUID()
        )
    }

    private func calculateLayout(for events: [CalendarEvent], day: Date) -> [EventLayoutInfo] {
        EventLayoutCalculator.calculateLayout(
            for: events,
            on: day,
            containerWidth: containerWidth,
            hourHeight: hourHeight
        )
    }

    private func layoutInfo(for event: CalendarEvent, in layout: [EventLayoutInfo]) -> EventLayoutInfo? {
        layout.first { $0.event.id == event.id }
    }
}
