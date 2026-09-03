import Foundation

/// Destinations, shared between the iOS app and the share extension.
///
/// Backed by app-group `UserDefaults`: the payload is a handful of coordinates
/// and names, so there is nothing here that warrants a database.
final class DestinationStore {
    static let shared = DestinationStore()

    private let defaults: UserDefaults
    private let destinationsKey = "destinations"
    private let pendingKey = "pendingDestinationID"
    /// Two shares of the same place should update one entry rather than pile up.
    private let duplicateRadius: Double = 25

    /// - Parameter defaults: overridden in tests; defaults to the app group,
    ///   falling back to standard defaults when the group is not provisioned.
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? AppGroup.sharedDefaults ?? .standard
    }

    // MARK: - Reading

    func all() -> [Destination] {
        guard let data = defaults.data(forKey: destinationsKey) else { return [] }
        do {
            return try JSONDecoder.walkArrow.decode([Destination].self, from: data)
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            // Corrupt or older-format data: start clean rather than wedge the UI.
            return []
        }
    }

    func destination(with id: UUID) -> Destination? {
        all().first { $0.id == id }
    }

    // MARK: - Writing

    /// Adds a destination, replacing any existing entry for the same place.
    ///
    /// - Returns: the stored destination, which keeps the existing `id` when it
    ///   replaced a nearby entry.
    @discardableResult
    func add(_ destination: Destination) -> Destination {
        var current = all()
        var stored = destination

        if let index = current.firstIndex(where: { isSamePlace($0, destination) }) {
            stored.id = current[index].id
            current[index] = stored
        } else {
            current.append(stored)
        }
        persist(current)
        return stored
    }

    func remove(id: UUID) {
        persist(all().filter { $0.id != id })
        if pendingDestinationID == id { pendingDestinationID = nil }
    }

    func removeAll() {
        persist([])
        pendingDestinationID = nil
    }

    /// The destination the share extension most recently handed over, so the
    /// app or the watch can offer it first.
    var pendingDestinationID: UUID? {
        get {
            guard let raw = defaults.string(forKey: pendingKey) else { return nil }
            return UUID(uuidString: raw)
        }
        set {
            if let newValue {
                defaults.set(newValue.uuidString, forKey: pendingKey)
            } else {
                defaults.removeObject(forKey: pendingKey)
            }
        }
    }

    // MARK: - Helpers

    private func isSamePlace(_ lhs: Destination, _ rhs: Destination) -> Bool {
        GeoMath.distance(from: lhs.point, to: rhs.point) <= duplicateRadius
            && lhs.name == rhs.name
    }

    private func persist(_ destinations: [Destination]) {
        do {
            let data = try JSONEncoder.walkArrow.encode(destinations)
            defaults.set(data, forKey: destinationsKey)
        } catch {
            // Nothing useful to do: the caller cannot fix an encoding failure
            // of our own model, and losing one save is preferable to crashing.
        }
    }
}
