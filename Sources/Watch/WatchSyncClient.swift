import Combine
import Foundation
import WatchConnectivity

/// The watch's end of the phone link.
///
/// The watch is the one that asks: it pulls the destination list on launch and
/// requests routes when the user picks a place or walks off the route. That
/// direction matters — a `WCSession` message from the watch will wake the iOS
/// app in the background, so the user never has to open the phone app after
/// sharing a place from Naver Map.
final class WatchSyncClient: NSObject, ObservableObject {
    @Published private(set) var payload: SyncPayload?
    @Published private(set) var isReachable = false
    /// Set when a request could not be delivered at all.
    @Published private(set) var lastError: String?

    private var session: WCSession? {
        WCSession.isSupported() ? .default : nil
    }

    /// Last payload, kept on disk so relaunching mid-walk does not lose the route.
    private let cacheURL: URL = {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent("last-sync-payload.json")
    }()

    override init() {
        super.init()
        payload = loadCachedPayload()
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
        // The received context survives launches, so apply it before any
        // round trip completes.
        if let context = SyncPayload.decode(from: session.receivedApplicationContext) {
            apply(context)
        }
    }

    // MARK: - Outbound

    func requestSync() {
        send([SyncKey.syncRequest: true])
    }

    func requestNavigation(destinationID: UUID, origin: GeoPoint?, reason: NavigationRequest.Reason) {
        let request = NavigationRequest(destinationID: destinationID, origin: origin, reason: reason)
        do {
            send(try request.messageBody())
        } catch {
            lastError = "요청을 만들지 못했습니다."
        }
    }

    func stopNavigation() {
        send([SyncKey.stopNavigation: true])
        // Clear locally straight away; the phone's confirmation may not arrive
        // for a while and the user has already asked to stop.
        if var current = payload {
            current.route = nil
            current.status = .idle
            apply(current)
        }
    }

    /// Sends immediately when the phone is reachable, and queues otherwise.
    ///
    /// `transferUserInfo` is the fallback rather than a retry loop because it
    /// is delivered by the system once the phone comes back, which is exactly
    /// the behaviour wanted when the phone is briefly out of range.
    private func send(_ message: [String: Any]) {
        guard let session, session.activationState == .activated else {
            lastError = "아이폰과 연결되지 않았습니다."
            return
        }
        lastError = nil

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { [weak self] _ in
                DispatchQueue.main.async {
                    session.transferUserInfo(message)
                    self?.lastError = nil
                }
            }
        } else {
            session.transferUserInfo(message)
        }
    }

    // MARK: - Inbound

    private func apply(_ newPayload: SyncPayload) {
        // Contexts can arrive out of order; never replace newer state with older.
        if let existing = payload, existing.sentAt > newPayload.sentAt { return }

        payload = newPayload
        cache(newPayload)
    }

    private func cache(_ newPayload: SyncPayload) {
        do {
            try JSONEncoder.walkArrow.encode(newPayload).write(to: cacheURL, options: .atomic)
        } catch {
            // The cache is a convenience; losing it costs one pull from the phone.
        }
    }

    private func loadCachedPayload() -> SyncPayload? {
        guard let data = try? Data(contentsOf: cacheURL),
              let payload = try? JSONDecoder.walkArrow.decode(SyncPayload.self, from: data) else {
            return nil
        }
        // Relaunching hours later must not resume guidance along a route the
        // walker has long since left.
        return payload.discardingStaleRoute()
    }
}

extension WatchSyncClient: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.isReachable = session.isReachable
            guard activationState == .activated else { return }
            if let context = SyncPayload.decode(from: session.receivedApplicationContext) {
                self?.apply(context)
            }
            self?.requestSync()
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.isReachable = session.isReachable
            if session.isReachable { self?.requestSync() }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let context = SyncPayload.decode(from: applicationContext) else { return }
        DispatchQueue.main.async { [weak self] in self?.apply(context) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let context = SyncPayload.decode(from: message) else { return }
        DispatchQueue.main.async { [weak self] in self?.apply(context) }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let context = SyncPayload.decode(from: userInfo) else { return }
        DispatchQueue.main.async { [weak self] in self?.apply(context) }
    }
}
