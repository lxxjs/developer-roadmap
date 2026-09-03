import Foundation

/// Where the user told us they want to walk to.
struct Destination: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var point: GeoPoint
    var address: String?
    var source: DestinationSource
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        point: GeoPoint,
        address: String? = nil,
        source: DestinationSource,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.point = point
        self.address = address
        self.source = source
        self.createdAt = createdAt
    }
}

enum DestinationSource: String, Codable, Sendable {
    /// Arrived through the iOS share sheet from Naver Map.
    case naverShare
    /// Typed in by hand (coordinates or an address we geocoded).
    case manual
    /// Picked from a MapKit search in the iPhone app.
    case search

    var displayName: String {
        switch self {
        case .naverShare: return "네이버지도"
        case .manual: return "직접 입력"
        case .search: return "검색"
        }
    }
}
