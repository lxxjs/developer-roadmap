import XCTest
#if canImport(WalkArrowCore)
@testable import WalkArrowCore
#endif

final class StoreAndSyncTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: DestinationStore!
    private let suiteName = "walkarrow.tests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = DestinationStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func destination(_ name: String, latitude: Double, longitude: Double) -> Destination {
        Destination(
            name: name,
            point: GeoPoint(latitude: latitude, longitude: longitude),
            source: .naverShare
        )
    }

    func testRoundTrip() {
        let saved = store.add(destination("강남역", latitude: 37.4979, longitude: 127.0276))
        XCTAssertEqual(store.all().count, 1)
        XCTAssertEqual(store.destination(with: saved.id)?.name, "강남역")
    }

    /// Sharing the same place twice should update one entry, not accumulate.
    func testNearbySamePlaceReplacesInsteadOfDuplicating() {
        let first = store.add(destination("강남역", latitude: 37.4979, longitude: 127.0276))
        // Ten metres away, same name: the same place as far as the user cares.
        let moved = GeoMath.point(from: first.point, east: 10, north: 0)
        let second = store.add(destination("강남역", latitude: moved.latitude, longitude: moved.longitude))

        XCTAssertEqual(store.all().count, 1)
        XCTAssertEqual(second.id, first.id, "the identifier should be kept so a running route still matches")
    }

    func testDistinctPlacesBothPersist() {
        store.add(destination("강남역", latitude: 37.4979, longitude: 127.0276))
        store.add(destination("서울시청", latitude: 37.5665, longitude: 126.9780))
        XCTAssertEqual(store.all().count, 2)
    }

    func testRemoveClearsPendingSelection() {
        let saved = store.add(destination("회사", latitude: 37.5, longitude: 127.0))
        store.pendingDestinationID = saved.id
        store.remove(id: saved.id)

        XCTAssertTrue(store.all().isEmpty)
        XCTAssertNil(store.pendingDestinationID)
    }

    func testCorruptDataDoesNotCrash() {
        defaults.set(Data("not json".utf8), forKey: "destinations")
        XCTAssertEqual(store.all(), [], "unreadable storage should read as empty, not throw")
    }

    func testSyncPayloadSurvivesTheDictionaryHop() throws {
        let destination = destination("강남역", latitude: 37.4979, longitude: 127.0276)
        let route = WalkRoute(
            destination: destination,
            points: [GeoPoint(latitude: 37.49, longitude: 127.02), destination.point],
            steps: [RouteStep(instruction: "직진", distance: 100, distanceAlongRoute: 0)],
            totalDistance: 100,
            expectedTravelTime: 80
        )
        let payload = SyncPayload(destinations: [destination], route: route, status: .routed)

        let decoded = SyncPayload.decode(from: try payload.messageBody())
        XCTAssertEqual(decoded?.status, .routed)
        XCTAssertEqual(decoded?.route?.id, route.id)
        XCTAssertEqual(decoded?.destinations.first?.name, "강남역")
    }

    func testNavigationRequestSurvivesTheDictionaryHop() throws {
        let request = NavigationRequest(
            destinationID: UUID(),
            origin: GeoPoint(latitude: 37.5, longitude: 127.0),
            reason: .reroute
        )
        let decoded = NavigationRequest.decode(from: try request.messageBody())

        XCTAssertEqual(decoded?.destinationID, request.destinationID)
        XCTAssertEqual(decoded?.reason, .reroute)
        XCTAssertEqual(decoded?.origin?.latitude ?? 0, 37.5, accuracy: 1e-9)
    }

    func testDecodingIgnoresUnrelatedMessages() {
        XCTAssertNil(SyncPayload.decode(from: [SyncKey.syncRequest: true]))
        XCTAssertNil(NavigationRequest.decode(from: [SyncKey.stopNavigation: true]))
    }
}
