import Foundation

/// Turns a wrapped angle into a continuously increasing one.
///
/// SwiftUI's `rotationEffect` interpolates between the numbers it is given, so
/// handing it 179° then -179° makes the arrow sweep the whole way round instead
/// of nudging 2°. Accumulating the signed deltas keeps every change short.
///
/// Lives in the shared layer rather than beside the view that uses it because
/// it is pure arithmetic, and being here is what lets it be tested.
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
