import XCTest
#if canImport(WalkArrowCore)
@testable import WalkArrowCore
#endif

final class PolylineTests: XCTestCase {
    private let origin = GeoPoint(latitude: 37.4979, longitude: 127.0276)

    func testProjectionMeasuresPerpendicularDistance() {
        let end = GeoMath.point(from: origin, east: 0, north: 200)
        let polyline = Polyline(points: [origin, end])
        let onPath = GeoMath.point(from: origin, east: 0, north: 100)

        for offset in [0.0, 10, 25, 41, 80] {
            let location = GeoMath.point(from: onPath, east: offset, north: 0)
            let projection = polyline.projection(of: location)
            XCTAssertEqual(projection?.distanceFromPath ?? -1, offset, accuracy: 0.1)
            XCTAssertEqual(projection?.distanceAlongRoute ?? -1, 100, accuracy: 0.1)
        }
    }

    func testProjectionClampsToSegmentEnds() {
        let end = GeoMath.point(from: origin, east: 0, north: 100)
        let polyline = Polyline(points: [origin, end])

        // 50 m before the start: the nearest path point is the start itself.
        let before = GeoMath.point(from: origin, east: 0, north: -50)
        let projection = polyline.projection(of: before)
        XCTAssertEqual(projection?.t ?? -1, 0, accuracy: 1e-6)
        XCTAssertEqual(projection?.distanceAlongRoute ?? -1, 0, accuracy: 0.1)
        XCTAssertEqual(projection?.distanceFromPath ?? -1, 50, accuracy: 0.1)
    }

    /// The window counts segments *beyond* the start index, so zero means one
    /// segment. Pinned explicitly because the tracker's off-route behaviour
    /// depends on the search really being bounded.
    func testForwardWindowLimitsTheSearch() {
        var points = [origin]
        for _ in 0..<20 {
            points.append(GeoMath.point(from: points.last!, east: 0, north: 10))
        }
        let polyline = Polyline(points: points)
        let farEnd = points.last!

        XCTAssertEqual(
            polyline.projection(of: farEnd, searchingFromSegment: 0, window: 0)?.segmentIndex,
            0,
            "a zero window must not look past the starting segment"
        )
        XCTAssertEqual(
            polyline.projection(of: farEnd, searchingFromSegment: 0, window: 1)?.segmentIndex,
            1,
            "a window of one admits the next segment"
        )
        XCTAssertEqual(
            polyline.projection(of: farEnd, searchingFromSegment: 0, window: nil)?.segmentIndex,
            points.count - 2,
            "no window searches to the end"
        )
    }

    func testPointAtDistanceInterpolatesAndClamps() {
        let corner = GeoMath.point(from: origin, east: 0, north: 200)
        let end = GeoMath.point(from: corner, east: 300, north: 0)
        let polyline = Polyline(points: [origin, corner, end])

        let quarter = polyline.point(atDistanceAlongRoute: 100)!
        XCTAssertEqual(GeoMath.distance(from: origin, to: quarter), 100, accuracy: 0.5)

        XCTAssertEqual(polyline.point(atDistanceAlongRoute: -10)!, origin)
        XCTAssertEqual(polyline.point(atDistanceAlongRoute: 99_999)!, end)
    }

    func testTurnLookupSkipsTurnsAlreadyPassed() {
        let first = GeoMath.point(from: origin, east: 0, north: 100)
        let second = GeoMath.point(from: first, east: 100, north: 0)
        let third = GeoMath.point(from: second, east: 0, north: 100)
        let polyline = Polyline(points: [origin, first, second, third])

        XCTAssertEqual(polyline.turnIndices, [1, 2])
        XCTAssertEqual(polyline.distanceAlongRoute(ofTurnAfter: 0) ?? -1, 100, accuracy: 1)
        XCTAssertEqual(polyline.distanceAlongRoute(ofTurnAfter: 120) ?? -1, 200, accuracy: 1)
        XCTAssertNil(polyline.distanceAlongRoute(ofTurnAfter: 250))
    }

    func testGentleBendIsNotATurn() {
        // Three points bending by 10 degrees: below the corner threshold.
        let mid = GeoMath.point(from: origin, east: 0, north: 100)
        let radians = GeoMath.radians(10)
        let end = GeoMath.point(from: mid, east: 100 * sin(radians), north: 100 * cos(radians))
        let polyline = Polyline(points: [origin, mid, end])

        XCTAssertTrue(polyline.turnIndices.isEmpty)
    }

    /// Simplification has to collapse a dense path without moving it.
    func testSimplificationKeepsShapeAndRespectsCap() {
        var points = [origin]
        var heading = 0.0
        for index in 0..<600 {
            if index % 80 == 0 { heading += 90 }
            let radians = GeoMath.radians(heading)
            points.append(
                GeoMath.point(
                    from: points.last!,
                    east: 5 * sin(radians),
                    north: 5 * cos(radians)
                )
            )
        }
        let dense = Polyline(points: points)
        let simplified = dense.simplified(tolerance: 2, maxPoints: 500)

        XCTAssertLessThan(simplified.count, dense.count / 10, "a straight run should collapse")
        XCTAssertEqual(simplified.totalDistance, dense.totalDistance, accuracy: 5)
        XCTAssertEqual(simplified.points.first, dense.points.first)
        XCTAssertEqual(simplified.points.last, dense.points.last)
    }

    /// Hitting the cap must reduce resolution, not delete the route's shape.
    ///
    /// Every vertex of this zigzag is a real corner, so raising the tolerance
    /// until the count fits would flatten 4 km of path into one straight
    /// segment — an arrow pointing at the destination rather than along the
    /// way there. Decimation has to take over instead.
    func testSimplificationUnderCapKeepsShapeRatherThanFlattening() {
        var points = [origin]
        for index in 0..<400 {
            let east = index.isMultiple(of: 2) ? 20.0 : -20.0
            points.append(GeoMath.point(from: points.last!, east: east, north: 10))
        }
        let dense = Polyline(points: points)
        let simplified = dense.simplified(tolerance: 2, maxPoints: 50)

        XCTAssertLessThanOrEqual(simplified.count, 50, "the transfer cap is a hard limit")
        XCTAssertGreaterThan(
            simplified.count,
            2,
            "escalating the tolerance to fit the cap collapsed this to its chord"
        )
        XCTAssertEqual(simplified.points.first, points.first)
        XCTAssertEqual(simplified.points.last, points.last)

        // Dropping most of a 400-vertex zigzag necessarily loses its amplitude,
        // so the surviving length says nothing useful. What must hold is that
        // every remaining point is a real vertex of the original route: the
        // arrow then always aims at somewhere the path actually goes, at lower
        // resolution, rather than at an invented straight line.
        let original = Set(points)
        for point in simplified.points {
            XCTAssertTrue(original.contains(point), "simplification must not invent points")
        }
    }

    func testShortPolylinesAreLeftAlone() {
        let end = GeoMath.point(from: origin, east: 0, north: 10)
        let polyline = Polyline(points: [origin, end])
        XCTAssertEqual(polyline.simplified().count, 2)
        XCTAssertNil(Polyline(points: [origin]).projection(of: origin))
        XCTAssertNil(Polyline(points: []).point(atDistanceAlongRoute: 0))
    }
}
