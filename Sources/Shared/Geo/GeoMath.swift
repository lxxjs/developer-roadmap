import Foundation

/// Spherical-earth geometry, plus a local tangent-plane approximation used for
/// the short-range segment maths.
///
/// The tangent plane is only ever applied over a single polyline segment (tens
/// of metres), where it is exact to well under a centimetre; over 1.8 km it
/// still only drifts 5 cm, which is far below walking GPS noise.
enum GeoMath {
    /// IUGG mean earth radius, in metres.
    static let earthRadius: Double = 6_371_008.8

    static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }

    /// Wraps a bearing into `0..<360`.
    static func normalizedBearing(_ bearing: Double) -> Double {
        let wrapped = bearing.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    /// Initial great-circle bearing from `origin` to `target`, in degrees
    /// clockwise from true north.
    static func initialBearing(from origin: GeoPoint, to target: GeoPoint) -> Double {
        let lat1 = radians(origin.latitude)
        let lat2 = radians(target.latitude)
        let deltaLon = radians(target.longitude - origin.longitude)

        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        return normalizedBearing(degrees(atan2(y, x)))
    }

    /// Great-circle (haversine) distance in metres.
    static func distance(from origin: GeoPoint, to target: GeoPoint) -> Double {
        let lat1 = radians(origin.latitude)
        let lat2 = radians(target.latitude)
        let deltaLat = lat2 - lat1
        let deltaLon = radians(target.longitude - origin.longitude)

        let haversine = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(haversine)))
    }

    /// Signed angle from `heading` to `target`, in `(-180, 180]`.
    ///
    /// This is what the watch rotates the arrow by: positive turns clockwise
    /// (to the user's right), negative anticlockwise.
    static func relativeAngle(target: Double, heading: Double) -> Double {
        var difference = (target - heading).truncatingRemainder(dividingBy: 360)
        if difference > 180 { difference -= 360 }
        if difference <= -180 { difference += 360 }
        return difference
    }

    /// `point` expressed as metres east/north of `origin` on a local tangent plane.
    static func localOffset(of point: GeoPoint, from origin: GeoPoint) -> (east: Double, north: Double) {
        let latitudeRadians = radians(origin.latitude)
        let east = radians(point.longitude - origin.longitude) * earthRadius * cos(latitudeRadians)
        let north = radians(point.latitude - origin.latitude) * earthRadius
        return (east, north)
    }

    /// Inverse of `localOffset(of:from:)`.
    static func point(from origin: GeoPoint, east: Double, north: Double) -> GeoPoint {
        let latitudeRadians = radians(origin.latitude)
        let latitude = origin.latitude + degrees(north / earthRadius)
        let longitude = origin.longitude + degrees(east / (earthRadius * cos(latitudeRadians)))
        return GeoPoint(latitude: latitude, longitude: longitude)
    }
}
