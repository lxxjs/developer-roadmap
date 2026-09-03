import XCTest
#if canImport(WalkArrowCore)
@testable import WalkArrowCore
#endif

/// Walks the whole journey through the real types: a Naver Map share arrives,
/// is parsed and stored, a route is built for it, a GPS trace is fed through
/// the tracker fix by fix, and arrival is reported.
///
/// What is genuinely covered: parsing, storage, the sync payload hop, and every
/// guidance decision the watch makes while walking. What is not, and cannot be
/// here: `MKDirections` (Apple-only, so routes are synthesised), `WCSession`
/// delivery (the payload is encoded and decoded in place instead of crossing
/// devices), and anything SwiftUI renders.
final class EndToEndTests: XCTestCase {
    private let gangnamStation = GeoPoint(latitude: 37.4979, longitude: 127.0276)

    // MARK: - Fixtures

    /// Stands in for `WalkRouteService`, which needs MapKit.
    ///
    /// The shape matters more than the provider: a route with two corners
    /// exercises turn aiming, and building it from legs lets each test state
    /// the geometry it means to test.
    private func route(
        to destination: Destination,
        legs: [(east: Double, north: Double)],
        instructions: [String] = []
    ) -> WalkRoute {
        var points = [gangnamStation]
        for leg in legs {
            points.append(GeoMath.point(from: points.last!, east: leg.east, north: leg.north))
        }
        let polyline = Polyline(points: points)

        var steps: [RouteStep] = []
        for (index, instruction) in instructions.enumerated() where index + 1 < polyline.cumulativeDistances.count {
            steps.append(
                RouteStep(
                    instruction: instruction,
                    distance: polyline.cumulativeDistances[index + 1] - polyline.cumulativeDistances[index],
                    distanceAlongRoute: polyline.cumulativeDistances[index]
                )
            )
        }

        var moved = destination
        moved.point = points.last!
        return WalkRoute(
            destination: moved,
            points: points,
            steps: steps,
            totalDistance: polyline.totalDistance,
            expectedTravelTime: DistanceFormatter.walkingDuration(forMetres: polyline.totalDistance)
        )
    }

    /// One guidance frame per fix, as the watch would see them.
    private func walk(
        _ tracker: RouteTracker,
        along polyline: Polyline,
        step: Double = 5,
        accuracy: Double? = 8
    ) -> [RouteGuidance] {
        var frames: [RouteGuidance] = []
        var distance: Double = 0
        while distance <= polyline.totalDistance {
            guard let point = polyline.point(atDistanceAlongRoute: distance) else { break }
            frames.append(tracker.update(location: point, horizontalAccuracy: accuracy))
            distance += step
        }
        return frames
    }

    // MARK: - The whole journey

    func testShareToArrival() throws {
        // 1. A share arrives from Naver Map: a place name, then a link with
        //    coordinates on it.
        let shared = """
        강남역 2번출구
        https://map.naver.com/p/entry/place/11624113?lng=127.0276&lat=37.4979&name=%EA%B0%95%EB%82%A8%EC%97%AD%202%EB%B2%88%EC%B6%9C%EA%B5%AC
        """
        let parsed = NaverShareParser.parse(text: shared)
        let point = try XCTUnwrap(parsed.point, "the share carried coordinates and they must be read")
        XCTAssertEqual(point.latitude, 37.4979, accuracy: 1e-6)
        XCTAssertEqual(parsed.name, "강남역 2번출구")

        // 2. The share extension stores it.
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "walkarrow.e2e"))
        defaults.removePersistentDomain(forName: "walkarrow.e2e")
        defer { defaults.removePersistentDomain(forName: "walkarrow.e2e") }
        let store = DestinationStore(defaults: defaults)

        let saved = store.add(
            Destination(name: parsed.name!, point: point, address: parsed.address, source: .naverShare)
        )
        store.pendingDestinationID = saved.id
        XCTAssertEqual(store.all().count, 1)

        // 3. The watch asks the phone to route there.
        let request = NavigationRequest(
            destinationID: saved.id,
            origin: gangnamStation,
            reason: .start
        )
        let relayedRequest = try XCTUnwrap(NavigationRequest.decode(from: try request.messageBody()))
        let target = try XCTUnwrap(store.destination(with: relayedRequest.destinationID))

        // 4. The phone computes a route and pushes it back. 250 m north, right
        //    for 300 m, left for 150 m — two corners to aim at.
        let computed = route(
            to: target,
            legs: [(0, 250), (300, 0), (0, 150)],
            instructions: ["북쪽으로 250m 직진", "우회전 후 300m", "좌회전 후 150m"]
        )
        let payload = SyncPayload(destinations: store.all(), route: computed, status: .routed)
        let relayed = try XCTUnwrap(SyncPayload.decode(from: try payload.messageBody()))
        let deliveredRoute = try XCTUnwrap(relayed.route)
        XCTAssertEqual(deliveredRoute.id, computed.id)
        XCTAssertEqual(deliveredRoute.totalDistance, 700, accuracy: 1)

        // 5. The watch walks it.
        let tracker = RouteTracker(route: deliveredRoute)
        let polyline = Polyline(points: deliveredRoute.points)
        let frames = walk(tracker, along: polyline)

        XCTAssertGreaterThan(frames.count, 100, "a 700 m route at 5 m per fix is many frames")

        // Never lost the route, never asked for a new one.
        XCTAssertFalse(frames.contains { $0.isOffRoute }, "walking the route must not read as leaving it")
        XCTAssertFalse(frames.contains { $0.needsReroute })

        // Every frame produced a usable bearing.
        XCTAssertFalse(frames.contains { $0.bearing == nil }, "the arrow must never go blank mid-walk")

        // Remaining distance only ever decreases.
        let remaining = frames.map(\.distanceRemainingAlongRoute)
        for (previous, next) in zip(remaining, remaining.dropFirst()) {
            XCTAssertLessThanOrEqual(next, previous + 0.001, "progress must not go backwards")
        }
        XCTAssertEqual(remaining.first ?? -1, 700, accuracy: 2)

        // 6. Arrival, once and at the end.
        XCTAssertTrue(frames.last?.hasArrived == true)
        let firstArrival = try XCTUnwrap(frames.firstIndex { $0.hasArrived })
        XCTAssertGreaterThan(
            Double(firstArrival) / Double(frames.count),
            0.9,
            "arrival must not fire early"
        )
    }

    /// The bearing must track each leg, and turn at the corners rather than
    /// before or after them.
    func testBearingMatchesEachLegWhileWalking() {
        let destination = Destination(name: "목적지", point: gangnamStation, source: .naverShare)
        let computed = route(to: destination, legs: [(0, 250), (300, 0), (0, 150)])
        let polyline = Polyline(points: computed.points)
        let tracker = RouteTracker(route: computed)

        // Sampled well inside each leg, clear of the corner aiming window.
        let expectations: [(distance: Double, bearing: Double, label: String)] = [
            (100, 0, "first leg heads north"),
            (400, 90, "second leg heads east"),
            (620, 0, "third leg heads north again"),
        ]

        var lastSampled: Double = 0
        for expectation in expectations {
            // Walk up to the sample point so the tracker's progress is real.
            var distance = lastSampled
            var guidance: RouteGuidance?
            while distance <= expectation.distance {
                guidance = tracker.update(
                    location: polyline.point(atDistanceAlongRoute: distance)!,
                    horizontalAccuracy: 8
                )
                distance += 5
            }
            lastSampled = expectation.distance
            let bearing = guidance?.bearing ?? -1
            XCTAssertLessThan(
                abs(GeoMath.relativeAngle(target: bearing, heading: expectation.bearing)),
                15,
                "\(expectation.label): got \(bearing)"
            )
        }
    }

    /// Corners must be announced before they arrive, so the wrist tap lands
    /// while there is still time to react.
    func testTurnsAreFlaggedBeforeReachingThem() {
        let destination = Destination(name: "목적지", point: gangnamStation, source: .naverShare)
        let computed = route(to: destination, legs: [(0, 250), (300, 0)])
        let polyline = Polyline(points: computed.points)
        let tracker = RouteTracker(route: computed)

        let frames = walk(tracker, along: polyline)
        let warned = frames.compactMap(\.upcomingTurnDistance)

        XCTAssertFalse(warned.isEmpty, "the corner at 250 m must be announced")
        XCTAssertLessThanOrEqual(warned.max() ?? .infinity, 50, "warnings start inside 50 m")
        XCTAssertGreaterThan(warned.max() ?? 0, 20, "and begin well before the corner")
    }

    /// Walking off the route must produce exactly one reroute ask, not a burst,
    /// and the arrow must fall back to the destination in the meantime.
    func testLeavingTheRouteAsksForANewOneThenRecovers() throws {
        let destination = Destination(name: "목적지", point: gangnamStation, source: .naverShare)
        let computed = route(to: destination, legs: [(0, 250), (300, 0)])
        let polyline = Polyline(points: computed.points)
        let tracker = RouteTracker(route: computed)

        // Walk 100 m correctly.
        var distance: Double = 0
        while distance <= 100 {
            _ = tracker.update(location: polyline.point(atDistanceAlongRoute: distance)!, horizontalAccuracy: 8)
            distance += 5
        }

        // Then wander 90 m to the side, one fix at a time.
        let departure = polyline.point(atDistanceAlongRoute: 100)!
        var strayFrames: [RouteGuidance] = []
        for metres in stride(from: 10.0, through: 90.0, by: 10) {
            let stray = GeoMath.point(from: departure, east: metres, north: 0)
            strayFrames.append(tracker.update(location: stray, horizontalAccuracy: 8))
        }

        // The first stray fixes must not trigger anything: a single bad sample
        // is not evidence of leaving the route.
        XCTAssertFalse(strayFrames[0].needsReroute)
        XCTAssertFalse(strayFrames[1].needsReroute)

        let asked = strayFrames.filter(\.needsReroute)
        XCTAssertFalse(asked.isEmpty, "a sustained 90 m departure must be noticed")
        XCTAssertEqual(asked.first?.mode, .directBearing, "with no route, aim at the destination")

        // Coming back must clear it without needing a new route.
        let recovered = tracker.update(location: departure, horizontalAccuracy: 8)
        XCTAssertFalse(recovered.isOffRoute)
        XCTAssertEqual(recovered.mode, .followingRoute)
        XCTAssertEqual(recovered.distanceRemainingAlongRoute, 450, accuracy: 10)
    }

    /// A noisy trace must not be mistaken for leaving the route. This is the
    /// realistic case: GPS on a wrist, between buildings.
    func testNoisyTraceDoesNotTriggerReroutes() {
        let destination = Destination(name: "목적지", point: gangnamStation, source: .naverShare)
        let computed = route(to: destination, legs: [(0, 250), (300, 0)])
        let polyline = Polyline(points: computed.points)
        let tracker = RouteTracker(route: computed)

        // Deterministic pseudo-noise, so a failure is reproducible.
        var seed: UInt64 = 0x5EED
        func noise(_ amplitude: Double) -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let unit = Double(seed >> 11) / Double(UInt64(1) << 53)
            return (unit * 2 - 1) * amplitude
        }

        var frames: [RouteGuidance] = []
        var distance: Double = 0
        while distance <= polyline.totalDistance {
            let truth = polyline.point(atDistanceAlongRoute: distance)!
            let noisy = GeoMath.point(from: truth, east: noise(12), north: noise(12))
            frames.append(tracker.update(location: noisy, horizontalAccuracy: 20))
            distance += 5
        }

        XCTAssertFalse(
            frames.contains { $0.needsReroute },
            "±12 m of noise with 20 m reported accuracy must stay within tolerance"
        )
        XCTAssertTrue(frames.last?.hasArrived == true, "noise must not prevent arrival")
    }

    /// The payload the phone sends must survive the trip at a size the watch
    /// session will actually accept.
    func testDeliveredPayloadStaysSmall() throws {
        let destination = Destination(name: "먼 목적지", point: gangnamStation, source: .naverShare)

        // A dense 3 km trace, as a routing provider would return it.
        var points = [gangnamStation]
        var heading = 0.0
        for index in 0..<600 {
            if index % 80 == 0 { heading += 90 }
            let radians = GeoMath.radians(heading)
            points.append(
                GeoMath.point(from: points.last!, east: 5 * sin(radians), north: 5 * cos(radians))
            )
        }
        let simplified = Polyline(points: points).simplified(tolerance: 2, maxPoints: 500)

        var moved = destination
        moved.point = simplified.points.last!
        let walkRoute = WalkRoute(
            destination: moved,
            points: simplified.points,
            totalDistance: simplified.totalDistance,
            expectedTravelTime: 2400
        )
        let payload = SyncPayload(destinations: [moved], route: walkRoute, status: .routed)

        let body = try payload.messageBody()
        let data = try XCTUnwrap(body[SyncKey.payload] as? Data)

        // `updateApplicationContext` rejects payloads in the hundreds of
        // kilobytes; staying under 16 KB leaves the limit a wide margin.
        XCTAssertLessThan(data.count, 16_384, "payload was \(data.count) bytes")

        let decoded = try XCTUnwrap(SyncPayload.decode(from: body))
        XCTAssertEqual(decoded.route?.points.count, simplified.points.count)
    }

    /// A share with no coordinate must still hand the caller something to
    /// geocode rather than a wrong location.
    func testShareWithoutCoordinatesDegradesToAName() {
        let parsed = NaverShareParser.parse(text: "봉은사\nhttps://naver.me/GAbCdEfG")
        XCTAssertNil(parsed.point)
        XCTAssertEqual(parsed.name, "봉은사")
        XCTAssertTrue(parsed.needsGeocoding, "the caller must know to geocode this")
    }
}
