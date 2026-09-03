import Combine
import CoreLocation
import Foundation
import WatchConnectivity

/// The phone's side of the pair: answers the watch's requests, computes routes,
/// and pushes state back.
///
/// The watch drives. That is what makes the flow work without the user ever
/// opening this app: a `WCSession` message from the watch launches the iOS app
/// in the background, so a place shared from Naver Map can be walked to
/// straight from the wrist.
final class PhoneCoordinator: NSObject, ObservableObject {
    @Published private(set) var destinations: [Destination] = []
    @Published private(set) var status: SyncPayload.Status = .idle
    @Published private(set) var activeRoute: WalkRoute?
    @Published private(set) var failureMessage: String?
    @Published private(set) var isWatchReachable = false
    @Published private(set) var isWatchAppInstalled = false

    private let store: DestinationStore
    private let routeService = WalkRouteService()
    private let locationProvider = PhoneLocationProvider()

    /// Guards against MapKit throttling when the watch retries.
    private var lastRouteRequest: Date?
    private let routeRequestCooldown: TimeInterval = 5
    private var routingTask: Task<Void, Never>?

    private var session: WCSession? {
        WCSession.isSupported() ? .default : nil
    }

    /// A single instance, because the watch session has exactly one delegate
    /// and it must be the same object the UI observes.
    static let shared = PhoneCoordinator()

    init(store: DestinationStore = .shared) {
        self.store = store
        super.init()
        destinations = store.all()
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Re-reads the app group, which is how destinations saved by the share
    /// extension become visible — a different process wrote them, so there is
    /// no notification to rely on.
    func reloadDestinations() {
        destinations = store.all()
        pushPayload()
    }

    func remove(_ destination: Destination) {
        store.remove(id: destination.id)
        if activeRoute?.destination.id == destination.id {
            activeRoute = nil
        }
        reloadDestinations()
    }

    @discardableResult
    func add(_ destination: Destination) -> Destination {
        let stored = store.add(destination)
        reloadDestinations()
        return stored
    }

    /// Computes a route and pushes it to the watch.
    func route(to destination: Destination, origin: GeoPoint? = nil) {
        if let last = lastRouteRequest, Date().timeIntervalSince(last) < routeRequestCooldown {
            return
        }
        lastRouteRequest = Date()

        routingTask?.cancel()
        status = .routing
        failureMessage = nil
        pushPayload()

        routingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let start = try await self.resolveOrigin(preferring: origin)
                let route = try await self.routeService.walkingRoute(from: start, to: destination)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.activeRoute = route
                    self.status = .routed
                    self.failureMessage = nil
                    self.pushPayload()
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.status = .failed
                    self.failureMessage = Self.message(for: error)
                    self.pushPayload()
                }
            }
        }
    }

    func stopNavigation() {
        routingTask?.cancel()
        activeRoute = nil
        status = .idle
        failureMessage = nil
        pushPayload()
    }

    // MARK: - Origin

    /// Prefers the watch's own fix: it is on the user's wrist, whereas the
    /// phone may be in a bag several metres away — or, in the background-wake
    /// case, have no recent fix at all.
    private func resolveOrigin(preferring provided: GeoPoint?) async throws -> GeoPoint {
        if let provided, provided.isValid { return provided }
        return try await locationProvider.currentPoint()
    }

    private static func message(for error: Error) -> String {
        if let serviceError = error as? WalkRouteService.ServiceError {
            return serviceError.localizedDescription
        }
        if let locationError = error as? PhoneLocationProvider.ProviderError {
            return locationError.localizedDescription
        }
        return "경로를 계산하지 못했습니다."
    }

    // MARK: - Outbound

    /// Pushes the whole state as an application context.
    ///
    /// The context coalesces to the latest value and survives the watch app
    /// being asleep, which is what we want — a stale route is never worth
    /// delivering, and the newest one should be there when the watch wakes.
    private func pushPayload() {
        guard let session, session.activationState == .activated else { return }

        let payload = SyncPayload(
            destinations: destinations,
            route: activeRoute,
            status: status,
            failureMessage: failureMessage
        )

        do {
            let body = try payload.messageBody()
            try session.updateApplicationContext(body)
            // Also send directly when the watch is up, so the screen changes
            // without waiting for the system to deliver the context.
            if session.isReachable {
                session.sendMessage(body, replyHandler: nil, errorHandler: nil)
            }
        } catch {
            failureMessage = "워치로 전송하지 못했습니다."
        }
    }
}

// MARK: - WCSessionDelegate

extension PhoneCoordinator: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.isWatchReachable = session.isReachable
            self?.isWatchAppInstalled = session.isWatchAppInstalled
            if activationState == .activated { self?.reloadDestinations() }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Required on iOS: reactivate so a switched watch keeps working.
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.isWatchReachable = session.isReachable
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handle(userInfo)
    }

    private func handle(_ message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if message[SyncKey.stopNavigation] != nil {
                self.stopNavigation()
                return
            }

            if message[SyncKey.syncRequest] != nil {
                // The share extension may have written since we last looked.
                self.reloadDestinations()
                return
            }

            guard let request = NavigationRequest.decode(from: message) else { return }
            // Re-read first: the watch may be asking for something the share
            // extension saved while this app was not running.
            self.destinations = self.store.all()

            guard let destination = self.destinations.first(where: { $0.id == request.destinationID }) else {
                self.status = .failed
                self.failureMessage = "목적지를 찾지 못했습니다."
                self.pushPayload()
                return
            }

            if request.reason == .reroute {
                // A reroute is the tracker insisting; do not let the cooldown
                // from the original request suppress it.
                self.lastRouteRequest = nil
            }
            self.route(to: destination, origin: request.origin)
        }
    }
}
