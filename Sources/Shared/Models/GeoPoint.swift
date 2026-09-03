import Foundation

/// A WGS-84 coordinate.
///
/// Deliberately independent of CoreLocation so that the whole geometry layer
/// stays unit-testable on any platform, including a plain `swift test` run.
///
/// The coding keys are abbreviated because route polylines are arrays of this
/// type and they travel to the watch through `WCSession`, whose application
/// context has a hard size limit.
struct GeoPoint: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double

    enum CodingKeys: String, CodingKey {
        case latitude = "la"
        case longitude = "lo"
    }

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

extension GeoPoint {
    /// Both components finite, inside their valid ranges, and not Null Island.
    ///
    /// Null Island is excluded because `0, 0` is what a failed parse or an
    /// uninitialised struct produces, and treating it as a real destination
    /// would send the user off the Gulf of Guinea.
    var isValid: Bool {
        latitude.isFinite && longitude.isFinite
            && abs(latitude) <= 90
            && abs(longitude) <= 180
            && !(latitude == 0 && longitude == 0)
    }
}

#if canImport(CoreLocation)
import CoreLocation

extension GeoPoint {
    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
#endif
