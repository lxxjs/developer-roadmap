import CoreLocation
import Foundation
import MapKit

/// Computes walking routes with MapKit.
///
/// MapKit rather than Naver: Naver Map has no third-party plug-in surface, and
/// the Naver Cloud Directions API covers driving only, so there is no public
/// Naver walking-route endpoint to call. MapKit's walking directions are the
/// available option that actually returns a pedestrian path.
struct WalkRouteService {
    enum ServiceError: LocalizedError {
        case noRouteFound
        case provider(String)

        var errorDescription: String? {
            switch self {
            case .noRouteFound:
                return "도보 경로를 찾지 못했습니다."
            case .provider(let message):
                return message
            }
        }
    }

    /// Simplification applied before the route goes to the watch. At 2 m a
    /// dense 3 km route collapses by two orders of magnitude while its length
    /// changes by about 2 m.
    private let simplificationTolerance: Double = 2
    private let maximumPoints = 500

    func walkingRoute(from origin: GeoPoint, to destination: Destination) async throws -> WalkRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(
            placemark: MKPlacemark(coordinate: origin.coordinate)
        )
        request.destination = MKMapItem(
            placemark: MKPlacemark(coordinate: destination.point.coordinate)
        )
        request.transportType = .walking
        request.requestsAlternateRoutes = false

        let response = try await calculate(MKDirections(request: request))
        guard let route = response.routes.first else { throw ServiceError.noRouteFound }

        let (points, steps) = flatten(route)
        guard points.count >= 2 else { throw ServiceError.noRouteFound }

        let simplified = Polyline(points: points)
            .simplified(tolerance: simplificationTolerance, maxPoints: maximumPoints)

        return WalkRoute(
            destination: destination,
            points: simplified.points,
            steps: steps,
            totalDistance: route.distance,
            expectedTravelTime: route.expectedTravelTime
        )
    }

    /// `MKDirections.calculate` is completion-based on the deployment target,
    /// so it is bridged rather than awaited directly.
    private func calculate(_ directions: MKDirections) async throws -> MKDirections.Response {
        try await withCheckedThrowingContinuation { continuation in
            directions.calculate { response, error in
                if let response {
                    continuation.resume(returning: response)
                } else {
                    continuation.resume(
                        throwing: error.map { ServiceError.provider($0.localizedDescription) }
                            ?? ServiceError.noRouteFound
                    )
                }
            }
        }
    }

    /// Concatenates the step polylines into one path, recording where each
    /// step begins.
    ///
    /// Built from the steps rather than from `route.polyline` because the step
    /// boundaries are what map a position back to an instruction, and joining
    /// the pieces gives those offsets exactly instead of by re-projection.
    private func flatten(_ route: MKRoute) -> ([GeoPoint], [RouteStep]) {
        var points: [GeoPoint] = []
        var steps: [RouteStep] = []
        var travelled: Double = 0

        for step in route.steps {
            let stepPoints = step.polyline.geoPoints
            guard !stepPoints.isEmpty else { continue }

            steps.append(
                RouteStep(
                    instruction: step.instructions,
                    distance: step.distance,
                    distanceAlongRoute: travelled
                )
            )

            // Consecutive steps repeat the shared vertex; keep one copy so the
            // cumulative distances stay honest.
            var toAppend = stepPoints
            if let last = points.last, toAppend.first == last {
                toAppend.removeFirst()
            }
            points.append(contentsOf: toAppend)
            travelled += step.distance
        }

        // Some responses put the whole geometry on the route and leave the
        // steps thin; fall back so we never ship an empty path.
        if points.count < 2 {
            points = route.polyline.geoPoints
        }
        return (points, steps)
    }
}

extension MKPolyline {
    /// The polyline's vertices. `MKPolyline` only exposes them through a
    /// buffer-filling call, so it is wrapped once here.
    var geoPoints: [GeoPoint] {
        guard pointCount > 0 else { return [] }
        var coordinates = [CLLocationCoordinate2D](
            repeating: CLLocationCoordinate2D(),
            count: pointCount
        )
        getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        return coordinates.map(GeoPoint.init)
    }
}
