import XCTest
@testable import LawMaticCalendar

@MainActor
final class CalendarDisplaySettingsTests: XCTestCase {
    func testPersistentSettingsSurviveRelaunch() throws {
        let suite = "CalendarDisplaySettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = CalendarDisplaySettings(defaults: defaults)
        XCTAssertTrue(first.showWeekends)
        XCTAssertTrue(first.highlightWeekends)
        XCTAssertTrue(first.highlightHolidays)
        XCTAssertTrue(first.showWorkingDayMarkers)

        first.showWeekends = false
        first.showWorkingDayMarkers = false

        let relaunched = CalendarDisplaySettings(defaults: defaults)
        XCTAssertFalse(relaunched.showWeekends)
        XCTAssertTrue(relaunched.highlightWeekends)
        XCTAssertTrue(relaunched.highlightHolidays)
        XCTAssertFalse(relaunched.showWorkingDayMarkers)
    }

    /// Демо, тесты и превью не должны менять настройки пользователя.
    func testInMemorySettingsLeaveUserDefaultsAlone() {
        let key = "display.highlightHolidays"
        let before = UserDefaults.standard.object(forKey: key) as? Bool

        let settings = CalendarDisplaySettings()
        settings.highlightHolidays = !(before ?? true)

        XCTAssertEqual(UserDefaults.standard.object(forKey: key) as? Bool, before)
    }

    func testViewModelSharesSettingsWithTheSettingsWindow() {
        let settings = CalendarDisplaySettings()
        let viewModel = CalendarViewModel(
            store: InMemoryCalendarStore(),
            providers: MockProviderRegistry([]),
            display: settings
        )

        settings.showWeekends = false
        XCTAssertFalse(viewModel.kalendsDayConfiguration.showWeekends)

        viewModel.highlightWeekends = false
        XCTAssertFalse(settings.highlightWeekends)
    }
}
