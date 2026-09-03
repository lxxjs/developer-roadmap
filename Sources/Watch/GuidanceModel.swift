import Combine
import CoreLocation
import Foundation
import WatchKit

/// Drives the compass screen: folds each GPS fix through the route tracker,
/// asks the phone for a new route when the user leaves the old one, and fires
/// the haptics.
///
/// Everything here runs on the main thread by construction: `CLLocationManager`
/// calls its delegate on the thread it was created on, and `WatchSyncClient`
/// hops to main before publishing.
final class GuidanceModel: ObservableObject {
    @Published private(set) var guidance: RouteGuidance?
    @Published private(set) var destinations: [Destination] = []
    @Published private(set) var status: SyncPayload.Status = .idle
    @Published private(set) var failureMessage: String?
    /// Continuous rotation for the arrow, in degrees; see `RotationAccumulator`.
    @Published private(set) var arrowRotation: Double = 0
    @Published private(set) var isArrowResolved = false

    // Mirrors of the two child objects' state.
    //
    // A nested `ObservableObject` does not propagate through its parent, so a
    // view watching `GuidanceModel` would never redraw when the phone became
    // reachable or the compass started working. Republishing the few fields the
    // UI actually reads keeps the views observing one object.
    @Published private(set) var isPhoneReachable = false
    @Published private(set) var headingSource: WatchLocationProvider.HeadingSource = .unavailable
    @Published private(set) var needsCompassCalibration = false
    @Published private(set) var locationAuthorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var hasHeading = false
    /// Latest fix, mirrored so list rows can show a distance and redraw.
    @Published private(set) var currentPoint: GeoPoint?

    let location = WatchLocationProvider()
    let sync = WatchSyncClient()

    private var tracker: RouteTracker?
    private var activeRoute: WalkRoute?
    private var rotation = RotationAccumulator()
    private var cancellables = Set<AnyCancellable>()

    /// Rerouting is rate-limited: MapKit throttles directions requests, and a
    /// user cutting a corner should not trigger a burst of them.
    private var lastRerouteRequest: Date?
    private let rerouteCooldown: TimeInterval = 20

    private var hasAnnouncedArrival = false
    private var hasAnnouncedOffRoute = false
    private var lastTurnWarningDistance: Double?

    var route: WalkRoute? { activeRoute }
    var isNavigating: Bool { activeRoute != nil }

    init() {
        sync.$payload
            .compactMap { $0 }
            .sink { [weak self] payload in self?.apply(payload) }
            .store(in: &cancellables)

        location.$location
            .compactMap { $0 }
            .sink { [weak self] fix in
                self?.currentPoint = GeoPoint(fix.coordinate)
                self?.consume(fix)
            }
            .store(in: &cancellables)

        // The arrow has to answer to the wrist turning, not just to new fixes:
        // heading updates arrive many times a second, GPS every few metres.
        location.$heading
            .sink { [weak self] heading in
                self?.hasHeading = heading != nil
                self?.headingDidChange()
            }
            .store(in: &cancellables)

        sync.$isReachable.assign(to: &$isPhoneReachable)
        location.$headingSource.assign(to: &$headingSource)
        location.$needsCompassCalibration.assign(to: &$needsCompassCalibration)
        location.$authorizationStatus.assign(to: &$locationAuthorization)
    }

    func start() {
        sync.activate()
        location.start()
    }

    // MARK: - Commands

    func beginNavigation(to destination: Destination) {
        resetAnnouncements()
        status = .routing
        failureMessage = nil
        sync.requestNavigation(
            destinationID: destination.id,
            origin: location.location.map { GeoPoint($0.coordinate) },
            reason: .start
        )
    }

    func endNavigation() {
        activeRoute = nil
        tracker = nil
        guidance = nil
        isArrowResolved = false
        rotation = RotationAccumulator()
        resetAnnouncements()
        sync.stopNavigation()
    }

    // MARK: - Inbound state

    private func apply(_ payload: SyncPayload) {
        destinations = payload.destinations
        status = payload.status
        failureMessage = payload.failureMessage

        guard let incoming = payload.route else {
            if activeRoute != nil {
                activeRoute = nil
                tracker = nil
                guidance = nil
                isArrowResolved = false
            }
            return
        }

        // Only rebuild the tracker for a genuinely different route, so a
        // repeated context does not throw away accumulated progress.
        if incoming.id != activeRoute?.id {
            activeRoute = incoming
            tracker = RouteTracker(route: incoming)
            resetAnnouncements()
            // A fresh route means the previous off-route burst is resolved.
            lastRerouteRequest = nil
            if let fix = location.location { consume(fix) }
        }
    }

    // MARK: - Per-fix work

    private func consume(_ fix: CLLocation) {
        guard let tracker, fix.horizontalAccuracy >= 0 else { return }

        let updated = tracker.update(
            location: GeoPoint(fix.coordinate),
            horizontalAccuracy: fix.horizontalAccuracy
        )
        guidance = updated
        updateArrow(for: updated)
        announce(updated)

        if updated.needsReroute, !updated.hasArrived {
            requestRerouteIfDue()
        }
    }

    /// Rotates the arrow to `bearing - heading`, accumulated so it never spins
    /// the long way round when the value wraps past ±180°.
    private func updateArrow(for guidance: RouteGuidance) {
        guard let bearing = guidance.bearing, let heading = location.heading else {
            isArrowResolved = false
            return
        }
        rotation.update(to: GeoMath.relativeAngle(target: bearing, heading: heading))
        arrowRotation = rotation.value
        isArrowResolved = true
    }

    /// Recompute the arrow when only the heading moved.
    private func headingDidChange() {
        guard let guidance else { return }
        updateArrow(for: guidance)
    }

    private func requestRerouteIfDue() {
        guard let destination = activeRoute?.destination else { return }
        if let last = lastRerouteRequest, Date().timeIntervalSince(last) < rerouteCooldown {
            return
        }
        lastRerouteRequest = Date()
        status = .routing
        sync.requestNavigation(
            destinationID: destination.id,
            origin: location.location.map { GeoPoint($0.coordinate) },
            reason: .reroute
        )
    }

    // MARK: - Haptics

    /// Each cue fires once per event rather than once per fix, so walking along
    /// a corner does not buzz continuously.
    private func announce(_ guidance: RouteGuidance) {
        if guidance.hasArrived {
            if !hasAnnouncedArrival {
                hasAnnouncedArrival = true
                WKInterfaceDevice.current().play(.success)
            }
            return
        }
        hasAnnouncedArrival = false

        if guidance.isOffRoute {
            if !hasAnnouncedOffRoute {
                hasAnnouncedOffRoute = true
                WKInterfaceDevice.current().play(.retry)
            }
        } else {
            hasAnnouncedOffRoute = false
        }

        announceTurn(guidance)
    }

    /// Buzzes once as a corner comes inside 25 m, and re-arms only after the
    /// user is clear of it.
    private func announceTurn(_ guidance: RouteGuidance) {
        guard let distance = guidance.upcomingTurnDistance else {
            lastTurnWarningDistance = nil
            return
        }
        if distance <= 25, lastTurnWarningDistance == nil {
            lastTurnWarningDistance = distance
            WKInterfaceDevice.current().play(.directionUp)
        } else if distance > 40 {
            lastTurnWarningDistance = nil
        }
    }

    private func resetAnnouncements() {
        hasAnnouncedArrival = false
        hasAnnouncedOffRoute = false
        lastTurnWarningDistance = nil
    }
}

/// Turns a wrapped angle into a continuously increasing one.
///
/// SwiftUI's `rotationEffect` interpolates between the numbers it is given, so
/// handing it 179° then -179° makes the arrow sweep the whole way round instead
/// of nudging 2°. Accumulating the signed deltas keeps every change short.
struct RotationAccumulator {
    private(set) var value: Double = 0
    private var last: Double?

    mutating func update(to angle: Double) {
        if let last {
            value += GeoMath.relativeAngle(target: angle, heading: last)
        } else {
            value = angle
        }
        last = angle
    }
}
