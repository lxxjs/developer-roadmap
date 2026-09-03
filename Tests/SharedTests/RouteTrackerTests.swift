import XCTest
#if canImport(WalkArrowCore)
@testable import WalkArrowCore
#endif

final class RouteTrackerTests: XCTestCase {
    private let origin = GeoPoint(latitude: 37.4979, longitude: 127.0276)

    /// An L: 200 m north, then 300 m east.
    private func makeLRoute() -> (WalkRoute, Polyline) {
        let corner = GeoMath.point(from: origin, east: 0, north: 200)
        let end = GeoMath.point(from: corner, east: 300, north: 0)
        let points = [origin, corner, end]
        let polyline = Polyline(points: points)

        let route = WalkRoute(
            destination: Destination(name: "끝", point: end, source: .manual),
            points: points,
            steps: [
                RouteStep(instruction: "북쪽으로 직진", distance: 200, distanceAlongRoute: 0),
                RouteStep(instruction: "우회전 후 직진", distance: 300, distanceAlongRoute: 200),
            ],
            totalDistance: polyline.totalDistance,
            expectedTravelTime: 400
        )
        return (route, polyline)
    }

    func testPolylineLengthAndTurnDetection() {
        let (_, polyline) = makeLRoute()
        XCTAssertEqual(polyline.totalDistance, 500, accuracy: 0.5)
        XCTAssertEqual(polyline.turnIndices, [1], "the single 90 degree corner should be the only turn")
    }

    func testBearingFollowsEachLegOfTheRoute() {
        let (route, polyline) = makeLRoute()
        let tracker = RouteTracker(route: route)

        // First leg heads north.
        for distance in [0.0, 50, 100, 150] {
            let guidance = tracker.update(location: polyline.point(atDistanceAlongRoute: distance)!)
            XCTAssertEqual(guidance.bearing ?? -1, 0, accuracy: 1, "at \(distance) m")
            XCTAssertEqual(guidance.mode, .followingRoute)
        }
        // Second leg heads east.
        for distance in [220.0, 300, 400] {
            let guidance = tracker.update(location: polyline.point(atDistanceAlongRoute: distance)!)
            XCTAssertEqual(guidance.bearing ?? -1, 90, accuracy: 1, "at \(distance) m")
        }
    }

    /// The arrow must point at the corner rather than through the building on
    /// the inside of the turn.
    func testAimsAtCornerInsteadOfCuttingIt() {
        let (route, polyline) = makeLRoute()
        let tracker = RouteTracker(route: route)

        let guidance = tracker.update(location: polyline.point(atDistanceAlongRoute: 180)!)
        XCTAssertEqual(guidance.bearing ?? -1, 0, accuracy: 1)
        XCTAssertEqual(guidance.upcomingTurnDistance ?? -1, 20, accuracy: 1)
    }

    func testRemainingDistanceCountsDown() {
        let (route, polyline) = makeLRoute()
        let tracker = RouteTracker(route: route)

        let early = tracker.update(location: polyline.point(atDistanceAlongRoute: 100)!)
        let late = tracker.update(location: polyline.point(atDistanceAlongRoute: 400)!)
        XCTAssertEqual(early.distanceRemainingAlongRoute, 400, accuracy: 2)
        XCTAssertEqual(late.distanceRemainingAlongRoute, 100, accuracy: 2)
    }

    /// Reaching the destination must not swing the arrow to due north, which is
    /// what a bearing computed towards a zero-length baseline would give.
    func testBearingHoldsSteadyOnArrival() {
        let (route, polyline) = makeLRoute()
        let tracker = RouteTracker(route: route)

        _ = tracker.update(location: polyline.point(atDistanceAlongRoute: 470)!)
        let atEnd = tracker.update(location: polyline.point(atDistanceAlongRoute: 500)!)

        XCTAssertTrue(atEnd.hasArrived)
        XCTAssertEqual(atEnd.bearing ?? -1, 90, accuracy: 2, "arrival must not snap the arrow north")
    }

    func testArrivalRadius() {
        let (route, polyline) = makeLRoute()
        let tracker = RouteTracker(route: route)

        XCTAssertFalse(tracker.update(location: polyline.point(atDistanceAlongRoute: 460)!).hasArrived)
        XCTAssertTrue(tracker.update(location: polyline.point(atDistanceAlongRoute: 495)!).hasArrived)
    }

    /// A single stray fix must not trigger a reroute; a sustained departure must.
    func testOffRouteNeedsConfirmation() {
        let (route, polyline) = makeLRoute()
        let tracker = RouteTracker(route: route)
        let onRoute = polyline.point(atDistanceAlongRoute: 100)!
        let wayOff = GeoMath.point(from: onRoute, east: 120, north: 0)

        _ = tracker.update(location: onRoute)

        let first = tracker.update(location: wayOff)
        XCTAssertFalse(first.needsReroute, "one bad fix is not proof of leaving the route")

        _ = tracker.update(location: wayOff)
        let third = tracker.update(location: wayOff)
        XCTAssertTrue(third.needsReroute)
        XCTAssertEqual(third.mode, .directBearing, "off route, aim straight at the destination")
    }

    func testReturningToRouteClearsOffRouteState() {
        let (route, polyline) = makeLRoute()
        let tracker = RouteTracker(route: route)
        let onRoute = polyline.point(atDistanceAlongRoute: 100)!
        let wayOff = GeoMath.point(from: onRoute, east: 120, north: 0)

        for _ in 0..<4 { _ = tracker.update(location: wayOff) }
        XCTAssertTrue(tracker.update(location: wayOff).isOffRoute)

        let back = tracker.update(location: onRoute)
        XCTAssertFalse(back.isOffRoute)
        XCTAssertEqual(back.mode, .followingRoute)
    }

    /// Rejoining the route must correct progress, not keep the inflated value
    /// an excursion produced: a position 120 m to the side of the 100 m mark
    /// projects onto the far leg of this L at about 320 m.
    func testRejoiningTheRouteCorrectsProgress() {
        let (route, polyline) = makeLRoute()
        let tracker = RouteTracker(route: route)
        let onRoute = polyline.point(atDistanceAlongRoute: 100)!
        let wayOff = GeoMath.point(from: onRoute, east: 120, north: 0)

        _ = tracker.update(location: onRoute)
        for _ in 0..<4 { _ = tracker.update(location: wayOff) }

        let back = tracker.update(location: onRoute)
        XCTAssertFalse(back.isOffRoute)
        XCTAssertEqual(
            back.distanceRemainingAlongRoute,
            400,
            accuracy: 5,
            "progress should return to the 100 m mark, not stay at the detour's projection"
        )
    }

    /// Poor accuracy must widen the off-route threshold, or an urban canyon
    /// would trigger reroutes while the user walks a perfectly good path.
    func testPoorAccuracyDoesNotTriggerReroute() {
        let (route, polyline) = makeLRoute()
        let tracker = RouteTracker(route: route)
        let onRoute = polyline.point(atDistanceAlongRoute: 100)!
        let drifted = GeoMath.point(from: onRoute, east: 55, north: 0)

        for _ in 0..<5 {
            let guidance = tracker.update(location: drifted, horizontalAccuracy: 60)
            XCTAssertFalse(guidance.needsReroute, "55 m off with 60 m accuracy is within noise")
        }
    }

    /// The forward search window is what keeps a doubling-back route from
    /// snapping progress onto the wrong leg. Verified numerically before the
    /// implementation: with 3 m between legs and GPS noise, an unbounded
    /// nearest-point search mislocates the walker about 40% of the time.
    func testProgressDoesNotJumpBackOnADoublingRoute() {
        let up = GeoMath.point(from: origin, east: 0, north: 100)
        let across = GeoMath.point(from: up, east: 3, north: 0)
        let down = GeoMath.point(from: across, east: 0, north: -100)
        let points = [origin, up, across, down]
        let polyline = Polyline(points: points)

        let route = WalkRoute(
            destination: Destination(name: "복귀 지점", point: down, source: .manual),
            points: points,
            totalDistance: polyline.totalDistance,
            expectedTravelTime: 200
        )
        let tracker = RouteTracker(route: route)

        // Walk the whole route, so the tracker's forward state is established.
        for distance in stride(from: 0.0, through: polyline.totalDistance, by: 10) {
            _ = tracker.update(location: polyline.point(atDistanceAlongRoute: distance)!)
        }

        // Near the end the walker is metres from the start of the route; the
        // remaining distance must reflect the far end, not the near one.
        let guidance = tracker.update(location: polyline.point(atDistanceAlongRoute: 195)!)
        XCTAssertLessThan(
            guidance.distanceRemainingAlongRoute,
            20,
            "progress snapped back to the outbound leg"
        )
    }

    func testInstructionTracksTheCurrentLeg() {
        let (route, polyline) = makeLRoute()
        let tracker = RouteTracker(route: route)

        let first = tracker.update(location: polyline.point(atDistanceAlongRoute: 50)!)
        XCTAssertEqual(first.instruction, "북쪽으로 직진")

        let second = tracker.update(location: polyline.point(atDistanceAlongRoute: 300)!)
        XCTAssertEqual(second.instruction, "우회전 후 직진")
    }

    func testEmptyRouteFallsBackToDirectBearing() {
        let destination = GeoMath.point(from: origin, east: 0, north: 500)
        let route = WalkRoute(
            destination: Destination(name: "직선", point: destination, source: .manual),
            points: [],
            totalDistance: 500,
            expectedTravelTime: 400
        )
        let tracker = RouteTracker(route: route)

        let guidance = tracker.update(location: origin)
        XCTAssertEqual(guidance.mode, .directBearing)
        XCTAssertEqual(guidance.bearing ?? -1, 0, accuracy: 1)
        XCTAssertFalse(guidance.needsReroute, "no geometry is not the same as leaving the route")
    }
}
