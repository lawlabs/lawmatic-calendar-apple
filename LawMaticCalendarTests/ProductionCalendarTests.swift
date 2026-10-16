import Kalends
import XCTest
@testable import LawMaticCalendar

@MainActor
final class ProductionCalendarTests: XCTestCase {
    private let catalog = ProductionCalendar.current

    func testSnapshotsCover2022Through2027() throws {
        XCTAssertNil(catalog.loadError)
        XCTAssertEqual(catalog.years, Set(2022...2027))
        for year in 2022...2027 {
            XCTAssertNotNil(try info(year, 6, 15), "\(year)")
        }
        XCTAssertNotNil(try info(2024, 2, 29))
        XCTAssertNil(try info(2028, 1, 1))
        XCTAssertNil(try info(2021, 12, 31))
    }

    func testKnownHolidaysTransfersAndShortenedDays() throws {
        let workingSaturday = try info(2025, 11, 1)
        XCTAssertEqual(workingSaturday?.kind, .transferredWorking)
        XCTAssertEqual(workingSaturday?.isShortened, true)
        XCTAssertEqual(try info(2025, 11, 3)?.kind, .transferredDayOff)
        XCTAssertEqual(try info(2026, 1, 9)?.kind, .transferredDayOff)
        XCTAssertEqual(try info(2026, 3, 9)?.kind, .transferredDayOff)
        XCTAssertEqual(try info(2026, 11, 3)?.kind, .working)
        XCTAssertEqual(try info(2026, 11, 3)?.isShortened, true)
        XCTAssertEqual(try info(2026, 11, 4)?.kind, .holiday)
        XCTAssertEqual(try info(2026, 12, 31)?.kind, .transferredDayOff)

        XCTAssertTrue(try info(2026, 11, 4)?.description?.contains("День народного единства") == true)
        let newYearEve = try info(2026, 12, 31)?.description
        XCTAssertTrue(newYearEve?.contains("04.01.2026") == true)
        XCTAssertTrue(newYearEve?.contains("1466") == true)

        let february = try info(2027, 2, 20)
        XCTAssertEqual(february?.kind, .transferredWorking)
        XCTAssertEqual(february?.isShortened, true)
        XCTAssertTrue(february?.description?.contains("RU-FEDERAL-2027-v2") == true)
    }

    func testBrokenSnapshotIsReportedSeparatelyFromAMissingYear() throws {
        XCTAssertNil(catalog.notice(for: [2026]))
        XCTAssertTrue(catalog.notice(for: [2028])?.contains("не загружены") == true)
        XCTAssertFalse(catalog.notice(for: [2028])?.contains("не прочитан") == true)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("2024.json")
        try Data("""
        {"calendar":"OTHER","version":{"versionId":"x","year":2024,"status":"OFFICIAL"},"days":[]}
        """.utf8).write(to: url)

        let broken = ProductionCalendar.load(urls: [url])
        XCTAssertTrue(broken.years.isEmpty)
        XCTAssertEqual(broken.failures[2024], "Неверный код производственного календаря.")
        let notice = broken.notice(for: [2024])
        XCTAssertTrue(notice?.contains("не прочитан") == true)
        XCTAssertTrue(notice?.contains("Неверный код") == true)
    }

    func testOrdinaryFridayKeepsTheDefaultExplanation() throws {
        let friday = try info(2026, 10, 16)
        XCTAssertEqual(friday?.kind, .working)
        XCTAssertEqual(friday?.isShortened, false)
        XCTAssertNil(friday?.description)
    }

    func testViewModelPrefersOverrideAndRestoresTheCatalog() throws {
        let viewModel = CalendarViewModel(store: InMemoryCalendarStore())
        let holiday = try currentDate(2026, 11, 4)
        XCTAssertEqual(viewModel.dayInfo(on: holiday)?.kind, .holiday)
        viewModel.selectedDate = holiday
        viewModel.viewMode = .day
        XCTAssertNil(viewModel.productionCalendarNotice)

        viewModel.setDayInfo(KalendsDayInfo(kind: .working), for: holiday)
        XCTAssertEqual(viewModel.dayInfo(on: holiday)?.kind, .working)
        viewModel.setDayInfo(nil, for: holiday)
        XCTAssertEqual(viewModel.dayInfo(on: holiday)?.kind, .holiday)

        let outside = try currentDate(2028, 1, 3)
        viewModel.selectedDate = outside
        XCTAssertNil(viewModel.dayInfo(on: outside))
        XCTAssertTrue(viewModel.productionCalendarNotice?.contains("2028") == true)
    }

    private func info(_ year: Int, _ month: Int, _ day: Int) throws -> KalendsDayInfo? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
        return catalog.info(on: date, calendar: calendar)
    }

    private func currentDate(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(Calendar.current.date(from: DateComponents(year: year, month: month, day: day)))
    }
}
