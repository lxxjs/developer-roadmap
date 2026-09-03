import Foundation

/// Distances as they are shown on the watch face.
///
/// Hand-rolled rather than `MeasurementFormatter` because the watch needs a
/// very short string and a predictable number of characters: metres below a
/// kilometre, one decimal place above it.
enum DistanceFormatter {
    static func string(fromMetres metres: Double) -> String {
        guard metres.isFinite, metres >= 0 else { return "—" }

        if metres < 1000 {
            return "\(Int(metres.rounded())) m"
        }
        let kilometres = metres / 1000
        if kilometres < 10 {
            return String(format: "%.1f km", kilometres)
        }
        return "\(Int(kilometres.rounded())) km"
    }

    /// A coarse walking estimate, used when no provider time is available.
    /// 1.35 m/s is the usual figure for adult walking pace.
    static func walkingDuration(forMetres metres: Double) -> TimeInterval {
        max(0, metres / 1.35)
    }

    static func durationString(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval >= 0 else { return "—" }
        let minutes = Int((interval / 60).rounded())
        if minutes < 1 { return "1분 미만" }
        if minutes < 60 { return "\(minutes)분" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)시간" : "\(hours)시간 \(remainder)분"
    }
}
