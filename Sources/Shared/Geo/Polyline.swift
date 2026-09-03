import Foundation

/// Where a location falls on a polyline.
struct SegmentProjection: Equatable {
    /// Index of the segment, i.e. the projection lies between `points[segmentIndex]`
    /// and `points[segmentIndex + 1]`.
    let segmentIndex: Int
    /// Position along that segment, `0...1`.
    let t: Double
    /// The projected point itself.
    let point: GeoPoint
    /// Perpendicular distance from the location to the path, in metres.
    let distanceFromPath: Double
    /// Cumulative distance from the start of the polyline to the projection.
    let distanceAlongRoute: Double
}

/// A route polyline with its cumulative distances and turn vertices precomputed.
///
/// Turn vertices are derived from the geometry rather than from the routing
/// provider's step list: step boundaries can be coarse, and the arrow needs to
/// know about every real corner so it aims *at* the corner instead of cutting
/// across it.
struct Polyline {
    let points: [GeoPoint]
    /// `cumulativeDistances[i]` is the distance from `points[0]` to `points[i]`.
    /// Always the same length as `points`, and starts at zero.
    let cumulativeDistances: [Double]
    /// Indices of vertices where the direction changes appreciably.
    let turnIndices: [Int]

    var count: Int { points.count }
    var isEmpty: Bool { points.isEmpty }
    var totalDistance: Double { cumulativeDistances.last ?? 0 }

    init(points: [GeoPoint], turnAngleThreshold: Double = 25) {
        self.points = points

        var cumulative: [Double] = []
        cumulative.reserveCapacity(points.count)
        var running: Double = 0
        for (index, point) in points.enumerated() {
            if index > 0 {
                running += GeoMath.distance(from: points[index - 1], to: point)
            }
            cumulative.append(running)
        }
        self.cumulativeDistances = cumulative

        var turns: [Int] = []
        if points.count >= 3 {
            for index in 1..<(points.count - 1) {
                let incoming = GeoMath.initialBearing(from: points[index - 1], to: points[index])
                let outgoing = GeoMath.initialBearing(from: points[index], to: points[index + 1])
                if abs(GeoMath.relativeAngle(target: outgoing, heading: incoming)) >= turnAngleThreshold {
                    turns.append(index)
                }
            }
        }
        self.turnIndices = turns
    }

    private init(points: [GeoPoint], cumulativeDistances: [Double], turnIndices: [Int]) {
        self.points = points
        self.cumulativeDistances = cumulativeDistances
        self.turnIndices = turnIndices
    }

    /// Nearest point on the path to `location`.
    ///
    /// `startIndex` and `window` bound the search to segments the user could
    /// plausibly be on. That bound is not an optimisation — it is what keeps a
    /// route that doubles back on itself from snapping progress to the wrong
    /// leg. With legs 3 m apart and ±5 m of GPS noise, an unbounded nearest
    /// search mislocates the user 42% of the time; a forward window never does.
    ///
    /// - Parameter window: how many segments *beyond* `startIndex` to consider.
    ///   `0` searches only the segment at `startIndex`; `nil` searches to the
    ///   end of the polyline.
    func projection(
        of location: GeoPoint,
        searchingFromSegment startIndex: Int = 0,
        window: Int? = nil
    ) -> SegmentProjection? {
        guard points.count >= 2 else { return nil }

        let lastSegment = points.count - 2
        let lowerBound = min(max(0, startIndex), lastSegment)
        let upperBound = window.map { min(lastSegment, lowerBound + $0) } ?? lastSegment

        var best: SegmentProjection?
        for index in lowerBound...upperBound {
            let start = points[index]
            let end = points[index + 1]

            let segment = GeoMath.localOffset(of: end, from: start)
            let relative = GeoMath.localOffset(of: location, from: start)
            let squaredLength = segment.east * segment.east + segment.north * segment.north

            let t: Double
            if squaredLength <= 0 {
                t = 0
            } else {
                let dot = relative.east * segment.east + relative.north * segment.north
                t = min(max(dot / squaredLength, 0), 1)
            }

            let projectedEast = segment.east * t
            let projectedNorth = segment.north * t
            let deltaEast = relative.east - projectedEast
            let deltaNorth = relative.north - projectedNorth
            let offPath = (deltaEast * deltaEast + deltaNorth * deltaNorth).squareRoot()

            if offPath < (best?.distanceFromPath ?? .infinity) {
                let segmentLength = cumulativeDistances[index + 1] - cumulativeDistances[index]
                best = SegmentProjection(
                    segmentIndex: index,
                    t: t,
                    point: GeoMath.point(from: start, east: projectedEast, north: projectedNorth),
                    distanceFromPath: offPath,
                    distanceAlongRoute: cumulativeDistances[index] + t * segmentLength
                )
            }
        }
        return best
    }

    /// The point `distance` metres along the path, clamped to its ends.
    func point(atDistanceAlongRoute distance: Double) -> GeoPoint? {
        guard let first = points.first, let last = points.last else { return nil }
        if distance <= 0 { return first }
        if distance >= totalDistance { return last }

        for index in 0..<(points.count - 1) where cumulativeDistances[index + 1] >= distance {
            let segmentLength = cumulativeDistances[index + 1] - cumulativeDistances[index]
            guard segmentLength > 0 else { return points[index] }
            let t = (distance - cumulativeDistances[index]) / segmentLength
            let segment = GeoMath.localOffset(of: points[index + 1], from: points[index])
            return GeoMath.point(from: points[index], east: segment.east * t, north: segment.north * t)
        }
        return last
    }

    /// Distance along the path of the first turn strictly beyond `distance`.
    func distanceAlongRoute(ofTurnAfter distance: Double) -> Double? {
        for index in turnIndices where cumulativeDistances[index] > distance {
            return cumulativeDistances[index]
        }
        return nil
    }

    /// Ramer–Douglas–Peucker simplification, with a hard cap on the result.
    ///
    /// The cap matters because the polyline is sent through the watch
    /// connectivity application context, which has a size limit.
    ///
    /// When the first pass does not fit, the tolerance is raised — but only a
    /// little. Escalating it freely erases real corners: a 4 km zigzag whose
    /// vertices sit 20 m off the straight line collapses to a single straight
    /// segment once the tolerance passes 20 m, which would point the arrow at
    /// the destination instead of along the path. Past a modest ceiling,
    /// uniform decimation is used instead, because dropping every other vertex
    /// keeps the route's shape at lower resolution rather than deleting it.
    func simplified(tolerance: Double = 2, maxPoints: Int = 500) -> Polyline {
        guard points.count > 2, tolerance > 0, maxPoints > 1 else { return self }

        let toleranceCeiling = tolerance * 4
        var currentTolerance = tolerance
        var result = Polyline.reduce(points: points, tolerance: currentTolerance)
        while result.count > maxPoints, currentTolerance * 2 <= toleranceCeiling {
            currentTolerance *= 2
            result = Polyline.reduce(points: points, tolerance: currentTolerance)
        }
        if result.count > maxPoints {
            let step = max(2, Int((Double(result.count) / Double(maxPoints)).rounded(.up)))
            var decimated = result.enumerated().compactMap { $0.offset % step == 0 ? $0.element : nil }
            if let last = result.last, decimated.last != last { decimated.append(last) }
            result = decimated
        }
        return Polyline(points: result)
    }

    private static func reduce(points: [GeoPoint], tolerance: Double) -> [GeoPoint] {
        guard points.count > 2 else { return points }

        var keep = Set([0, points.count - 1])
        // Explicit stack rather than recursion: a dense route can be thousands
        // of points deep and this also runs on the watch.
        var stack: [(Int, Int)] = [(0, points.count - 1)]

        while let (low, high) = stack.popLast() {
            guard high > low + 1 else { continue }

            let start = points[low]
            let chord = GeoMath.localOffset(of: points[high], from: start)
            let chordLength = (chord.east * chord.east + chord.north * chord.north).squareRoot()

            var worstDistance = -1.0
            var worstIndex = low
            for index in (low + 1)..<high {
                let relative = GeoMath.localOffset(of: points[index], from: start)
                let distance: Double
                if chordLength <= 0 {
                    distance = (relative.east * relative.east + relative.north * relative.north).squareRoot()
                } else {
                    let dot = relative.east * chord.east + relative.north * chord.north
                    let t = min(max(dot / (chordLength * chordLength), 0), 1)
                    let dEast = relative.east - chord.east * t
                    let dNorth = relative.north - chord.north * t
                    distance = (dEast * dEast + dNorth * dNorth).squareRoot()
                }
                if distance > worstDistance {
                    worstDistance = distance
                    worstIndex = index
                }
            }

            if worstDistance > tolerance {
                keep.insert(worstIndex)
                stack.append((low, worstIndex))
                stack.append((worstIndex, high))
            }
        }
        return keep.sorted().map { points[$0] }
    }
}
