import CoreGraphics
import XCTest
@testable import LawMaticCalendar

final class CalendarColorMappingTests: XCTestCase {
    func testAppleCalendarColorsKeepTheirHue() {
        let cases: [(String, EventColor)] = [
            ("#FF2968", .red),
            ("#FF9500", .orange),
            ("#FFCC00", .yellow),
            ("#63DA38", .green),
            ("#1BADF8", .blue),
            ("#CC73E1", .purple),
            ("#A2845E", .brown),
        ]
        for (hex, expected) in cases {
            XCTAssertEqual(EventColor.nearest(to: hex, fallback: .gray), expected, hex)
        }
    }

    /// Saturated colors that the old RGB distance to the pastel palette
    /// turned gray (purple) and brown (green).
    func testSaturatedColorsDoNotTurnGrayOrBrown() {
        XCTAssertEqual(EventColor.nearest(to: "#A259D9", fallback: .blue), .purple)
        XCTAssertEqual(EventColor.nearest(to: "#8E24AA", fallback: .blue), .purple)
        XCTAssertEqual(EventColor.nearest(to: "#34C759", fallback: .blue), .green)
        XCTAssertEqual(EventColor.nearest(to: "#0B8043", fallback: .blue), .green)
    }

    func testColorlessAndDarkColorsAreGray() {
        XCTAssertEqual(EventColor.nearest(to: "#8E8E93", fallback: .blue), .gray)
        XCTAssertEqual(EventColor.nearest(to: "#C8C8C8", fallback: .blue), .gray)
        XCTAssertEqual(EventColor.nearest(to: "#101010", fallback: .blue), .gray)
    }

    func testUnreadableHexFallsBack() {
        XCTAssertEqual(EventColor.nearest(to: nil, fallback: .blue), .blue)
        XCTAssertEqual(EventColor.nearest(to: "#FFF", fallback: .blue), .blue)
        XCTAssertEqual(EventColor.nearest(to: "not a color", fallback: .blue), .blue)
    }

    func testEventKitColorsAreConvertedToSRGB() throws {
        let displayP3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let p3Purple = try XCTUnwrap(CGColor(colorSpace: displayP3, components: [0.75, 0.42, 0.86, 1]))
        let p3Green = try XCTUnwrap(CGColor(colorSpace: displayP3, components: [0, 1, 0, 1]))
        let gray = CGColor(gray: 0.6, alpha: 1)

        let purpleHex = try XCTUnwrap(AppleCalendarProvider.hexString(from: p3Purple))
        let greenHex = try XCTUnwrap(AppleCalendarProvider.hexString(from: p3Green))
        let grayHex = try XCTUnwrap(AppleCalendarProvider.hexString(from: gray))

        XCTAssertEqual(EventColor.nearest(to: purpleHex, fallback: .gray), .purple, purpleHex)
        // Pure P3 green lies outside sRGB; the clamped value is still green.
        XCTAssertEqual(EventColor.nearest(to: greenHex, fallback: .gray), .green, greenHex)
        XCTAssertEqual(EventColor.nearest(to: grayHex, fallback: .blue), .gray, grayHex)
        XCTAssertNil(AppleCalendarProvider.hexString(from: nil))
    }
}
