import XCTest
#if canImport(WalkArrowCore)
@testable import WalkArrowCore
#endif

final class DistanceFormatterTests: XCTestCase {
    func testMetresBelowAKilometre() {
        XCTAssertEqual(DistanceFormatter.string(fromMetres: 0), "0 m")
        XCTAssertEqual(DistanceFormatter.string(fromMetres: 7.4), "7 m")
        XCTAssertEqual(DistanceFormatter.string(fromMetres: 999), "999 m")
    }

    func testKilometres() {
        XCTAssertEqual(DistanceFormatter.string(fromMetres: 1000), "1.0 km")
        XCTAssertEqual(DistanceFormatter.string(fromMetres: 1440), "1.4 km")
        XCTAssertEqual(DistanceFormatter.string(fromMetres: 25_400), "25 km")
    }

    func testInvalidInput() {
        XCTAssertEqual(DistanceFormatter.string(fromMetres: -1), "—")
        XCTAssertEqual(DistanceFormatter.string(fromMetres: .nan), "—")
        XCTAssertEqual(DistanceFormatter.string(fromMetres: .infinity), "—")
    }

    func testDurations() {
        XCTAssertEqual(DistanceFormatter.durationString(20), "1분 미만")
        XCTAssertEqual(DistanceFormatter.durationString(300), "5분")
        XCTAssertEqual(DistanceFormatter.durationString(3600), "1시간")
        XCTAssertEqual(DistanceFormatter.durationString(3900), "1시간 5분")
        XCTAssertEqual(DistanceFormatter.durationString(-1), "—")
    }
}
