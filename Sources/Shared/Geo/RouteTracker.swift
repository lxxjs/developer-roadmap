import Foundation

/// Everything the watch needs to draw one frame of guidance.
struct RouteGuidance: Equatable {
    enum Mode: Equatable {
        /// Aiming at a point along the computed route.
        case followingRoute
        /// Off the route — aiming straight at the destination until a new
        /// route arrives.
        case directBearing
    }

    var mode: Mode
    /// Absolute bearing to aim at, degrees clockwise from true north.
    ///
    /// `nil` only while no bearing has ever been resolvable, which happens if
    /// the very first fix already sits on top of the aim point.
    var bearing: Double?
    /// The point `bearing` was computed towards.
    var target: GeoPoint
    /// Straight-line distance to the destination.
    var distanceToDestination: Double
    /// Distance still to walk along the route.
    var distanceRemainingAlongRoute: Double
    /// Perpendicular distance from the route.
    var distanceFromRoute: Double
    var isOffRoute: Bool
    /// Set once being off-route has been confirmed across several fixes, so a
    /// single bad GPS sample cannot trigger a reroute.
    var needsReroute: Bool
    var hasArrived: Bool
    /// Distance to the next corner, when one is close enough to warn about.
    var upcomingTurnDistance: Double?
    /// Instruction for the leg the user is about to walk, when available.
    var instruction: String?
}

/// Matches a stream of GPS fixes against a route and produces the arrow bearing.
///
/// The tracker is stateful on purpose: progress along the route is kept
/// monotonic, and being off-route has to be confirmed over several fixes
/// before it is reported.
final class RouteTracker {
    struct Configuration {
        /// How far ahead along the route to aim. Large enough that GPS jitter
        /// does not swing the arrow, small enough to still read as "the way
        /// the path goes right here".
        var lookaheadDistance: Double = 30
        /// If the aim point is closer than this, keep the previous bearing
        /// rather than computing one from a near-zero baseline — otherwise the
        /// arrow snaps to due north as the user reaches the destination.
        var minimumAimDistance: Double = 3
        /// Never aim at a corner nearer than this, or the arrow sticks to a
        /// corner the user is standing on.
        var minimumTurnAimDistance: Double = 5
        var offRouteThreshold: Double = 40
        /// Hysteresis: coming back this close counts as rejoining the route.
        var onRouteThreshold: Double = 20
        var offRouteConfirmations: Int = 3
        var arrivalRadius: Double = 20
        /// Segments to look ahead when matching a fix to the route.
        var forwardSearchWindow: Int = 40
        /// Report a corner once it is within this distance.
        var turnWarningDistance: Double = 50
        /// Horizontal accuracy beyond this is treated as extra off-route slack
        /// so a poor fix in an urban canyon does not trigger a reroute.
        var accuracyToleratedWithoutSlack: Double = 10

        init() {}
    }

    let route: WalkRoute
    let configuration: Configuration

    private let polyline: Polyline
    private var lastSegmentIndex = 0
    private var travelledDistance: Double = 0
    private var offRouteStreak = 0
    private var isOffRouteConfirmed = false
    private var lastResolvedBearing: Double?

    init(route: WalkRoute, configuration: Configuration = Configuration()) {
        self.route = route
        self.configuration = configuration
        self.polyline = Polyline(points: route.points)
    }

    /// Forget accumulated progress, e.g. after the user restarts navigation.
    func reset() {
        lastSegmentIndex = 0
        travelledDistance = 0
        offRouteStreak = 0
        isOffRouteConfirmed = false
        lastResolvedBearing = nil
    }

    /// Fold one GPS fix into the tracker and return the resulting guidance.
    ///
    /// - Parameter horizontalAccuracy: metres of uncertainty, if known.
    func update(location: GeoPoint, horizontalAccuracy: Double? = nil) -> RouteGuidance {
        let destination = route.destination.point
        let distanceToDestination = GeoMath.distance(from: location, to: destination)
        let hasArrived = distanceToDestination <= configuration.arrivalRadius

        // A route with fewer than two points carries no geometry to follow.
        guard polyline.count >= 2,
              let projection = project(location) else {
            return directGuidance(
                from: location,
                to: destination,
                distanceToDestination: distanceToDestination,
                hasArrived: hasArrived,
                needsReroute: false
            )
        }

        let wasOffRoute = isOffRouteConfirmed
        updateOffRouteState(projection: projection, horizontalAccuracy: horizontalAccuracy)

        if isOffRouteConfirmed || wasOffRoute {
            // Either still off the route, or rejoining it on this fix: take the
            // projection at face value. Keeping the monotonic maximum across an
            // excursion would leave progress inflated, because a position off to
            // one side often projects onto a much later segment — walking 120 m
            // sideways at the 100 m mark projects onto the far leg at 320 m.
            lastSegmentIndex = projection.segmentIndex
            travelledDistance = projection.distanceAlongRoute
        } else {
            // Progress only ever moves forward while we are on the route; see
            // `Polyline.projection` for why the forward bound matters.
            lastSegmentIndex = max(lastSegmentIndex, projection.segmentIndex)
            travelledDistance = max(travelledDistance, projection.distanceAlongRoute)
        }

        let remaining = max(0, polyline.totalDistance - travelledDistance)

        guard !isOffRouteConfirmed else {
            var guidance = directGuidance(
                from: location,
                to: destination,
                distanceToDestination: distanceToDestination,
                hasArrived: hasArrived,
                needsReroute: true
            )
            guidance.distanceFromRoute = projection.distanceFromPath
            guidance.distanceRemainingAlongRoute = remaining
            return guidance
        }

        let aimDistance = aimDistanceAlongRoute()
        let target = polyline.point(atDistanceAlongRoute: aimDistance) ?? destination
        let bearing = resolveBearing(from: location, to: target)

        let nextTurn = polyline.distanceAlongRoute(ofTurnAfter: travelledDistance)
        let turnDistance = nextTurn.map { $0 - travelledDistance }

        return RouteGuidance(
            mode: .followingRoute,
            bearing: bearing,
            target: target,
            distanceToDestination: distanceToDestination,
            distanceRemainingAlongRoute: remaining,
            distanceFromRoute: projection.distanceFromPath,
            isOffRoute: false,
            needsReroute: false,
            hasArrived: hasArrived,
            upcomingTurnDistance: turnDistance.flatMap {
                $0 <= configuration.turnWarningDistance ? $0 : nil
            },
            instruction: instruction(at: travelledDistance)
        )
    }

    // MARK: - Pieces

    private func project(_ location: GeoPoint) -> SegmentProjection? {
        if isOffRouteConfirmed {
            // Search the whole route: the forward window is meaningless once we
            // no longer trust where we were.
            return polyline.projection(of: location)
        }
        return polyline.projection(
            of: location,
            searchingFromSegment: lastSegmentIndex,
            window: configuration.forwardSearchWindow
        )
    }

    private func updateOffRouteState(projection: SegmentProjection, horizontalAccuracy: Double?) {
        let slack = max(0, (horizontalAccuracy ?? 0) - configuration.accuracyToleratedWithoutSlack)
        let offThreshold = configuration.offRouteThreshold + slack

        if projection.distanceFromPath > offThreshold {
            offRouteStreak += 1
            if offRouteStreak >= configuration.offRouteConfirmations {
                isOffRouteConfirmed = true
            }
        } else if projection.distanceFromPath < configuration.onRouteThreshold + slack {
            offRouteStreak = 0
            isOffRouteConfirmed = false
        }
    }

    /// How far along the route to place the aim point.
    ///
    /// Normally a fixed lookahead, but pulled back to the next corner when one
    /// falls inside it — aiming past a corner would point the arrow through the
    /// building on the inside of the turn.
    private func aimDistanceAlongRoute() -> Double {
        var aim = travelledDistance + configuration.lookaheadDistance
        let earliestTurn = travelledDistance + configuration.minimumTurnAimDistance
        if let turn = polyline.distanceAlongRoute(ofTurnAfter: earliestTurn), turn < aim {
            aim = turn
        }
        return min(aim, polyline.totalDistance)
    }

    private func resolveBearing(from location: GeoPoint, to target: GeoPoint) -> Double? {
        guard GeoMath.distance(from: location, to: target) >= configuration.minimumAimDistance else {
            return lastResolvedBearing
        }
        let bearing = GeoMath.initialBearing(from: location, to: target)
        lastResolvedBearing = bearing
        return bearing
    }

    private func directGuidance(
        from location: GeoPoint,
        to destination: GeoPoint,
        distanceToDestination: Double,
        hasArrived: Bool,
        needsReroute: Bool
    ) -> RouteGuidance {
        RouteGuidance(
            mode: .directBearing,
            bearing: resolveBearing(from: location, to: destination),
            target: destination,
            distanceToDestination: distanceToDestination,
            distanceRemainingAlongRoute: distanceToDestination,
            distanceFromRoute: 0,
            isOffRoute: needsReroute,
            needsReroute: needsReroute,
            hasArrived: hasArrived,
            upcomingTurnDistance: nil,
            instruction: nil
        )
    }

    /// The instruction for the leg containing `distance` along the route.
    private func instruction(at distance: Double) -> String? {
        var match: RouteStep?
        for step in route.steps where step.distanceAlongRoute <= distance {
            match = step
        }
        let text = (match ?? route.steps.first)?.instruction
        return (text?.isEmpty ?? true) ? nil : text
    }
}
