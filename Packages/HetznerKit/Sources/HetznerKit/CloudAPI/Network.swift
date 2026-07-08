import Foundation

/// A Hetzner Cloud private network.
public struct Network: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let ipRange: String
    public let subnets: [NetworkSubnet]
    public let routes: [NetworkRoute]
    public let servers: [Int]
    public let protection: NetworkProtection
    public let labels: [String: String]
    public let created: Date
    public let exposeRoutesToVswitch: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name
        case ipRange = "ip_range"
        case subnets, routes, servers, protection, labels, created
        case exposeRoutesToVswitch = "expose_routes_to_vswitch"
    }

    public init(
        id: Int,
        name: String,
        ipRange: String,
        subnets: [NetworkSubnet],
        routes: [NetworkRoute],
        servers: [Int],
        protection: NetworkProtection,
        labels: [String: String],
        created: Date,
        exposeRoutesToVswitch: Bool?
    ) {
        self.id = id
        self.name = name
        self.ipRange = ipRange
        self.subnets = subnets
        self.routes = routes
        self.servers = servers
        self.protection = protection
        self.labels = labels
        self.created = created
        self.exposeRoutesToVswitch = exposeRoutesToVswitch
    }

    /// Labels decode leniently — see `decodeLenientLabels`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        ipRange = try container.decode(String.self, forKey: .ipRange)
        subnets = try container.decode([NetworkSubnet].self, forKey: .subnets)
        routes = try container.decode([NetworkRoute].self, forKey: .routes)
        servers = try container.decode([Int].self, forKey: .servers)
        protection = try container.decode(NetworkProtection.self, forKey: .protection)
        labels = try container.decodeLenientLabels(forKey: .labels)
        created = try container.decode(Date.self, forKey: .created)
        exposeRoutesToVswitch = try container.decodeIfPresent(Bool.self, forKey: .exposeRoutesToVswitch)
    }
}

/// Unknown wire values decode to `.unknown` instead of throwing.
public enum NetworkSubnetType: String, Codable, Sendable, Equatable {
    case cloud, server, vswitch
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NetworkSubnetType(rawValue: raw) ?? .unknown
    }
}

public struct NetworkSubnet: Codable, Sendable, Equatable {
    public let type: NetworkSubnetType
    public let ipRange: String?
    public let networkZone: String
    public let gateway: String?
    public let vswitchID: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case ipRange = "ip_range"
        case networkZone = "network_zone"
        case gateway
        case vswitchID = "vswitch_id"
    }

    public init(
        type: NetworkSubnetType,
        ipRange: String?,
        networkZone: String,
        gateway: String?,
        vswitchID: Int?
    ) {
        self.type = type
        self.ipRange = ipRange
        self.networkZone = networkZone
        self.gateway = gateway
        self.vswitchID = vswitchID
    }
}

public struct NetworkRoute: Codable, Sendable, Equatable {
    public let destination: String
    public let gateway: String

    enum CodingKeys: String, CodingKey { case destination, gateway }

    public init(destination: String, gateway: String) {
        self.destination = destination
        self.gateway = gateway
    }
}

public struct NetworkProtection: Codable, Sendable, Equatable {
    public let delete: Bool

    enum CodingKeys: String, CodingKey { case delete }

    public init(delete: Bool) {
        self.delete = delete
    }
}

/// Wire envelope for `GET /networks/{id}` and create/update responses → `{"network": {...}}`.
struct NetworkEnvelope: Decodable, Sendable {
    let network: Network
}

/// Input describing a subnet to attach when creating a network via
/// `createNetwork(name:ipRange:subnets:labels:)`.
public struct NetworkSubnetSpec: Sendable, Equatable {
    public let type: NetworkSubnetType
    public let ipRange: String
    public let networkZone: String

    public init(type: NetworkSubnetType, ipRange: String, networkZone: String) {
        self.type = type
        self.ipRange = ipRange
        self.networkZone = networkZone
    }
}
