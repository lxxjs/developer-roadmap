import CoreLocation
import Foundation

/// A one-shot location fix, used only as the fallback origin when the watch
/// did not send one.
///
/// Deliberately not a continuous stream: the watch supplies the origin in the
/// normal case, so the phone only needs a single fix, and holding location
/// updates open in a background-woken app would waste the user's battery.
final class PhoneLocationProvider: NSObject {
    enum ProviderError: LocalizedError {
        case denied
        case unavailable

        var errorDescription: String? {
            switch self {
            case .denied:
                return "위치 권한이 없어 출발지를 확인할 수 없습니다."
            case .unavailable:
                return "현재 위치를 확인할 수 없습니다."
            }
        }
    }

    private let manager = CLLocationManager()
    private var continuations: [CheckedContinuation<GeoPoint, Error>] = []
    /// A fix this recent is good enough to reuse rather than waking the GPS.
    private let freshnessWindow: TimeInterval = 30

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func currentPoint() async throws -> GeoPoint {
        if let cached = manager.location,
           Date().timeIntervalSince(cached.timestamp) < freshnessWindow,
           cached.horizontalAccuracy >= 0 {
            return GeoPoint(cached.coordinate)
        }

        switch manager.authorizationStatus {
        case .denied, .restricted:
            throw ProviderError.denied
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }

        return try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
            manager.requestLocation()
        }
    }

    private func finish(_ result: Result<GeoPoint, Error>) {
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume(with: result)
        }
    }
}

extension PhoneLocationProvider: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last, fix.horizontalAccuracy >= 0 else {
            finish(.failure(ProviderError.unavailable))
            return
        }
        finish(.success(GeoPoint(fix.coordinate)))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(ProviderError.unavailable))
    }
}
