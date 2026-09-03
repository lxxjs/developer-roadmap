import Foundation

/// Message keys for the `WCSession` traffic between phone and watch.
enum SyncKey {
    /// Phone → watch: the whole shared state, as an application context.
    static let payload = "payload"
    /// Watch → phone: start or recompute a route.
    static let navigationRequest = "navigationRequest"
    /// Watch → phone: send the current state back, used on watch launch to
    /// pull destinations without the user having to open the iPhone app.
    static let syncRequest = "syncRequest"
    /// Watch → phone: navigation was ended on the watch.
    static let stopNavigation = "stopNavigation"
}

/// The complete phone → watch state.
///
/// Sent as a `WCSession` application context, which coalesces to the latest
/// value — exactly the semantics wanted here, since an older route is never
/// worth delivering.
struct SyncPayload: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case idle
        case routing
        case routed
        case failed
    }

    var destinations: [Destination]
    var route: WalkRoute?
    var status: Status
    var failureMessage: String?
    var sentAt: Date

    init(
        destinations: [Destination] = [],
        route: WalkRoute? = nil,
        status: Status = .idle,
        failureMessage: String? = nil,
        sentAt: Date = Date()
    ) {
        self.destinations = destinations
        self.route = route
        self.status = status
        self.failureMessage = failureMessage
        self.sentAt = sentAt
    }
}

/// Watch → phone ask for a route.
struct NavigationRequest: Codable, Equatable, Sendable {
    enum Reason: String, Codable, Sendable {
        /// The user picked a destination on the watch.
        case start
        /// The tracker decided the user has left the route.
        case reroute
    }

    var destinationID: UUID
    /// Where to route from. The watch is on the user's wrist, so its own fix is
    /// a better origin than the phone's — which may be in a bag.
    var origin: GeoPoint?
    var reason: Reason
    var requestedAt: Date

    init(destinationID: UUID, origin: GeoPoint?, reason: Reason, requestedAt: Date = Date()) {
        self.destinationID = destinationID
        self.origin = origin
        self.reason = reason
        self.requestedAt = requestedAt
    }
}

// MARK: - Staleness

extension SyncPayload {
    /// How long a cached route stays usable.
    ///
    /// A walking route older than this is stale on its own merits — the walker
    /// is somewhere else by now, and resuming guidance from it would point them
    /// off a path they are no longer on. It also keeps the app inside the terms
    /// of route providers that cap how long their data may be retained; TMAP's
    /// pedestrian API allows 24 hours, so this sits well under it.
    static let maximumRouteAge: TimeInterval = 6 * 60 * 60

    /// Drops a route that has aged out, keeping everything else.
    ///
    /// Destinations survive: they are the user's own saved places, not the
    /// route provider's data, and they do not go stale.
    func discardingStaleRoute(
        olderThan maximumAge: TimeInterval = SyncPayload.maximumRouteAge,
        now: Date = Date()
    ) -> SyncPayload {
        guard let route, now.timeIntervalSince(route.createdAt) > maximumAge else {
            return self
        }
        var fresh = self
        fresh.route = nil
        fresh.status = .idle
        fresh.failureMessage = nil
        return fresh
    }
}

// MARK: - Dictionary transport

/// `WCSession` deals in `[String: Any]`, so each payload travels as one JSON
/// blob under a known key. Keeping it to a single `Data` value avoids relying
/// on which types the session is willing to serialise.
extension SyncPayload {
    func messageBody() throws -> [String: Any] {
        [SyncKey.payload: try JSONEncoder.walkArrow.encode(self)]
    }

    static func decode(from message: [String: Any]) -> SyncPayload? {
        guard let data = message[SyncKey.payload] as? Data else { return nil }
        return try? JSONDecoder.walkArrow.decode(SyncPayload.self, from: data)
    }
}

extension NavigationRequest {
    func messageBody() throws -> [String: Any] {
        [SyncKey.navigationRequest: try JSONEncoder.walkArrow.encode(self)]
    }

    static func decode(from message: [String: Any]) -> NavigationRequest? {
        guard let data = message[SyncKey.navigationRequest] as? Data else { return nil }
        return try? JSONDecoder.walkArrow.decode(NavigationRequest.self, from: data)
    }
}
