import Kalends
import Observation
import XCTest
@testable import LawMaticCalendar

@MainActor
final class CalendarDayPresentationTests: XCTestCase {
    func testDisplayOptionsHaveIndependentDefaultsAndReachKalends() {
        let viewModel = CalendarViewModel(store: InMemoryCalendarStore())
        XCTAssertTrue(viewModel.kalendsDayConfiguration.showWeekends)
        XCTAssertTrue(viewModel.kalendsDayConfiguration.highlightWeekends)
        XCTAssertTrue(viewModel.kalendsDayConfiguration.highlightHolidays)
        XCTAssertTrue(viewModel.kalendsDayConfiguration.showWorkingDayMarkers)

        viewModel.highlightWeekends = false
        XCTAssertTrue(viewModel.kalendsDayConfiguration.showWeekends)
        XCTAssertFalse(viewModel.kalendsDayConfiguration.highlightWeekends)
        XCTAssertTrue(viewModel.kalendsDayConfiguration.highlightHolidays)

        viewModel.showWeekends = false
        viewModel.showWorkingDayMarkers = false
        XCTAssertFalse(viewModel.kalendsDayConfiguration.showWeekends)
        XCTAssertTrue(viewModel.kalendsDayConfiguration.highlightHolidays)
        XCTAssertFalse(viewModel.kalendsDayConfiguration.showWorkingDayMarkers)
    }

    func testClassificationUpdatesAndRemovalReachExistingConfiguration() throws {
        let viewModel = CalendarViewModel(store: InMemoryCalendarStore())
        let calendar = Calendar.current
        let saturday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 19)))
        let afternoon = try XCTUnwrap(calendar.date(bySettingHour: 15, minute: 30, second: 0, of: saturday))
        let configuration = viewModel.kalendsDayConfiguration
        XCTAssertEqual(configuration.info(for: saturday, calendar: calendar).kind, .weekend)

        let workingSaturday = KalendsDayInfo(kind: .transferredWorking, isShortened: true)
        viewModel.setDayInfo(workingSaturday, for: afternoon)
        XCTAssertEqual(viewModel.dayInfo(on: saturday), workingSaturday)
        XCTAssertEqual(configuration.info(for: saturday, calendar: calendar), workingSaturday)
        XCTAssertFalse(configuration.info(for: afternoon, calendar: calendar).isNonWorking)

        viewModel.setDayInfo(nil, for: saturday)
        XCTAssertNil(viewModel.dayInfo(on: afternoon))
        XCTAssertEqual(configuration.info(for: afternoon, calendar: calendar).kind, .weekend)
    }

    func testDisplayOptionsAndDayInfoLeaveEventsAndStorageAlone() throws {
        let store = InMemoryCalendarStore(snapshot: CalendarSeedData.previewSnapshot())
        let viewModel = CalendarViewModel(store: store)
        let originalEvents = viewModel.events
        let persistedEvents = try store.loadEvents()
        viewModel.showWeekends = false
        viewModel.highlightHolidays = false
        viewModel.setDayInfo(KalendsDayInfo(kind: .holiday), for: Date())

        XCTAssertEqual(viewModel.events, originalEvents)
        XCTAssertEqual(try store.loadEvents(), persistedEvents)
        XCTAssertFalse(viewModel.hasPendingSaves)
    }

    func testKalendsProviderParticipatesInObservation() {
        let viewModel = CalendarViewModel(store: InMemoryCalendarStore())
        let configuration = viewModel.kalendsDayConfiguration
        let day = Date()
        let changed = expectation(description: "Day classification invalidates the view")
        withObservationTracking {
            _ = configuration.info(for: day, calendar: .current)
        } onChange: {
            changed.fulfill()
        }

        viewModel.setDayInfo(KalendsDayInfo(kind: .holiday), for: day)
        wait(for: [changed], timeout: 1)
    }

    func testSyntheticDemoHasHolidayTransferShortenedDayAndWorkingSaturday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Moscow"))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 23)))
        let days = CalendarSeedData.demoDayInfo(around: date, calendar: calendar)
        func info(_ day: Int) throws -> KalendsDayInfo? {
            days[try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: day)))]
        }

        XCTAssertEqual(days.count, 4)
        XCTAssertEqual(try info(21)?.kind, .holiday)
        XCTAssertEqual(try info(22)?.kind, .transferredDayOff)
        XCTAssertEqual(try info(24)?.isShortened, true)
        XCTAssertEqual(try info(26)?.kind, .transferredWorking)
        XCTAssertEqual(try info(26)?.isShortened, true)
        XCTAssertNil(try info(27))
        XCTAssertTrue(days.values.allSatisfy { $0.description?.hasPrefix("Демо:") == true })
    }
}
