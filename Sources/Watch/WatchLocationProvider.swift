import Combine
import CoreLocation
import Foundation

/// Position and heading from the watch's own sensors.
///
/// Heading is the interesting part. Apple Watch Series 5 and later have a
/// magnetometer, which is what gives a usable direction while standing still.
/// Where there is no compass we fall back to GPS course, which only becomes
/// meaningful once the user is actually moving.
final class WatchLocationProvider: NSObject, ObservableObject {
    enum HeadingSource: Equatable {
        case compass
        /// Derived from movement; needs the user to keep walking.
        case course
        case unavailable
    }

    @Published private(set) var location: CLLocation?
    /// Degrees clockwise from true north, smoothed.
    @Published private(set) var heading: Double?
    @Published private(set) var headingSource: HeadingSource = .unavailable
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    /// Set when the compass reports it needs a figure-of-eight wave.
    @Published private(set) var needsCompassCalibration = false

    private let manager = CLLocationManager()
    /// Circular exponential moving average of the heading, held as a unit
    /// vector so that averaging across the 0°/360° seam works.
    private var headingVector: (x: Double, y: Double)?
    /// Weight of each new sample. Low enough to kill magnetometer jitter,
    /// high enough that turning your wrist still feels immediate.
    private let smoothingFactor = 0.25
    /// Below this speed a GPS course is noise, not a direction.
    private let minimumCourseSpeed: Double = 0.6
    private let maximumCourseUncertainty: Double = 45

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        requestAuthorization()
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.headingFilter = 2
            manager.startUpdatingHeading()
        } else {
            headingSource = .course
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.stopUpdatingHeading()
        }
        headingVector = nil
        heading = nil
        headingSource = .unavailable
    }

    // MARK: - Smoothing

    /// Folds a raw heading into the smoothed value.
    ///
    /// Averaging the angles directly would swing wildly whenever samples
    /// straddle north (359° and 1° would average to 180°), so the average is
    /// taken over unit vectors instead.
    private func smooth(_ degrees: Double) -> Double {
        let radians = GeoMath.radians(degrees)
        let sample = (x: cos(radians), y: sin(radians))

        let updated: (x: Double, y: Double)
        if let current = headingVector {
            updated = (
                x: current.x + (sample.x - current.x) * smoothingFactor,
                y: current.y + (sample.y - current.y) * smoothingFactor
            )
        } else {
            updated = sample
        }
        headingVector = updated
        return GeoMath.normalizedBearing(GeoMath.degrees(atan2(updated.y, updated.x)))
    }
}

extension WatchLocationProvider: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last, latest.horizontalAccuracy >= 0 else { return }
        location = latest

        // Only stand in for the compass; never override a real magnetometer reading.
        guard !CLLocationManager.headingAvailable() else { return }

        if latest.speed >= minimumCourseSpeed,
           latest.course >= 0,
           latest.courseAccuracy >= 0,
           latest.courseAccuracy <= maximumCourseUncertainty {
            heading = smooth(latest.course)
            headingSource = .course
        } else if heading == nil {
            headingSource = .course
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // A negative accuracy means the reading is currently unusable.
        guard newHeading.headingAccuracy >= 0 else {
            needsCompassCalibration = true
            return
        }
        needsCompassCalibration = false

        // True heading needs a location fix to know magnetic declination; until
        // there is one, magnetic heading is the best available.
        let raw = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        guard raw >= 0 else { return }

        heading = smooth(raw)
        headingSource = .compass
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways {
            start()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A transient `kCLErrorLocationUnknown` is normal indoors and clears
        // itself; anything else is surfaced through the authorization status.
    }
}
