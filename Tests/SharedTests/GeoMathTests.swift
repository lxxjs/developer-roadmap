import XCTest
#if canImport(WalkArrowCore)
@testable import WalkArrowCore
#endif

final class GeoMathTests: XCTestCase {
    private let seoulCityHall = GeoPoint(latitude: 37.5665, longitude: 126.9780)

    func testBearingToCardinalDirections() {
        let cases: [(GeoPoint, Double, String)] = [
            (GeoPoint(latitude: 37.5765, longitude: 126.9780), 0, "north"),
            (GeoPoint(latitude: 37.5665, longitude: 126.9880), 90, "east"),
            (GeoPoint(latitude: 37.5565, longitude: 126.9780), 180, "south"),
            (GeoPoint(latitude: 37.5665, longitude: 126.9680), 270, "west"),
        ]

        for (target, expected, label) in cases {
            let bearing = GeoMath.initialBearing(from: seoulCityHall, to: target)
            let error = abs(GeoMath.relativeAngle(target: bearing, heading: expected))
            XCTAssertLessThan(error, 0.01, "bearing \(label) was \(bearing)")
        }
    }

    func testDistanceAgainstKnownSeparations() {
        // One degree of latitude on the mean sphere.
        XCTAssertEqual(
            GeoMath.distance(
                from: GeoPoint(latitude: 0, longitude: 0),
                to: GeoPoint(latitude: 1, longitude: 0)
            ),
            111_195,
            accuracy: 50
        )
        // Seoul to Busan city hall, ~325 km.
        XCTAssertEqual(
            GeoMath.distance(from: seoulCityHall, to: GeoPoint(latitude: 35.1798, longitude: 129.0750)),
            325_000,
            accuracy: 5_000
        )
    }

    func testRelativeAngleWrapsAcrossNorth() {
        XCTAssertEqual(GeoMath.relativeAngle(target: 10, heading: 350), 20, accuracy: 1e-9)
        XCTAssertEqual(GeoMath.relativeAngle(target: 350, heading: 10), -20, accuracy: 1e-9)
        XCTAssertEqual(GeoMath.relativeAngle(target: 0, heading: 90), -90, accuracy: 1e-9)
        XCTAssertEqual(GeoMath.relativeAngle(target: 90, heading: 0), 90, accuracy: 1e-9)
    }

    func testRelativeAngleStaysInRange() {
        for target in stride(from: 0.0, to: 360.0, by: 7) {
            for heading in stride(from: 0.0, to: 360.0, by: 11) {
                let angle = GeoMath.relativeAngle(target: target, heading: heading)
                XCTAssertGreaterThan(angle, -180.0001)
                XCTAssertLessThanOrEqual(angle, 180.0001)
            }
        }
    }

    func testLocalOffsetRoundTrips() {
        for (east, north) in [(50.0, 0.0), (0.0, 50.0), (300.0, -200.0), (-1000.0, 1500.0)] {
            let point = GeoMath.point(from: seoulCityHall, east: east, north: north)
            let offset = GeoMath.localOffset(of: point, from: seoulCityHall)
            XCTAssertEqual(offset.east, east, accuracy: 0.001)
            XCTAssertEqual(offset.north, north, accuracy: 0.001)
        }
    }

    func testGeoPointRejectsNullIslandAndOutOfRange() {
        XCTAssertFalse(GeoPoint(latitude: 0, longitude: 0).isValid)
        XCTAssertFalse(GeoPoint(latitude: 91, longitude: 0).isValid)
        XCTAssertFalse(GeoPoint(latitude: 0, longitude: 181).isValid)
        XCTAssertFalse(GeoPoint(latitude: .nan, longitude: 0).isValid)
        XCTAssertTrue(GeoPoint(latitude: 37.5, longitude: 127.0).isValid)
    }
}
