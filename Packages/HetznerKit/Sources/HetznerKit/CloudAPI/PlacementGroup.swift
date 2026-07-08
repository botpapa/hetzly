import Foundation

/// A Hetzner Cloud placement group — controls server co-location for
/// anti-affinity scheduling.
public struct PlacementGroup: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let labels: [String: String]
    public let type: PlacementGroupType
    public let servers: [Int]
    public let created: Date

    enum CodingKeys: String, CodingKey {
        case id, name, labels, type, servers, created
    }

    public init(
        id: Int,
        name: String,
        labels: [String: String],
        type: PlacementGroupType,
        servers: [Int],
        created: Date
    ) {
        self.id = id
        self.name = name
        self.labels = labels
        self.type = type
        self.servers = servers
        self.created = created
    }
}

/// Unknown wire values decode to `.unknown` instead of throwing.
public enum PlacementGroupType: String, Codable, Sendable, Equatable {
    case spread
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PlacementGroupType(rawValue: raw) ?? .unknown
    }
}

/// Wire envelope for `GET /placement_groups/{id}` and create responses →
/// `{"placement_group": {...}}`.
struct PlacementGroupEnvelope: Decodable, Sendable {
    let placementGroup: PlacementGroup

    enum CodingKeys: String, CodingKey {
        case placementGroup = "placement_group"
    }
}
