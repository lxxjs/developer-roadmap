import Foundation

/// A walking route, computed on the iPhone and handed to the watch.
///
/// `points` runs from the origin the route was requested at to the
/// destination, and is already simplified for transfer — see
/// `Polyline.simplified(tolerance:maxPoints:)`.
struct WalkRoute: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var destination: Destination
    var points: [GeoPoint]
    var steps: [RouteStep]
    var totalDistance: Double
    var expectedTravelTime: TimeInterval
    var createdAt: Date

    init(
        id: UUID = UUID(),
        destination: Destination,
        points: [GeoPoint],
        steps: [RouteStep] = [],
        totalDistance: Double,
        expectedTravelTime: TimeInterval,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.destination = destination
        self.points = points
        self.steps = steps
        self.totalDistance = totalDistance
        self.expectedTravelTime = expectedTravelTime
        self.createdAt = createdAt
    }
}

/// One leg of the route, as reported by the routing provider.
///
/// `distanceAlongRoute` is the cumulative distance from the route origin to
/// where this step *starts*, which is what lets the tracker map a position on
/// the polyline back to an instruction without re-projecting every step.
struct RouteStep: Codable, Hashable, Sendable {
    var instruction: String
    var distance: Double
    var distanceAlongRoute: Double

    init(instruction: String, distance: Double, distanceAlongRoute: Double) {
        self.instruction = instruction
        self.distance = distance
        self.distanceAlongRoute = distanceAlongRoute
    }
}
