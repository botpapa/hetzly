import Foundation

/// A Hetzner Cloud server.
public struct Server: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let status: ServerStatus
    public let created: Date
    public let publicNet: PublicNet
    public let serverType: ServerType
    public let datacenter: Datacenter
    public let labels: [String: String]
    public let locked: Bool
    public let protection: ServerProtection
    public let backupWindow: String?
    public let rescueEnabled: Bool
    public let primaryDiskSize: Int
    public let includedTraffic: Int64?
    public let outgoingTraffic: Int64?
    public let ingoingTraffic: Int64?

    enum CodingKeys: String, CodingKey {
        case id, name, status, created
        case publicNet = "public_net"
        case serverType = "server_type"
        case datacenter
        case labels, locked, protection
        case backupWindow = "backup_window"
        case rescueEnabled = "rescue_enabled"
        case primaryDiskSize = "primary_disk_size"
        case includedTraffic = "included_traffic"
        case outgoingTraffic = "outgoing_traffic"
        case ingoingTraffic = "ingoing_traffic"
    }

    public init(
        id: Int,
        name: String,
        status: ServerStatus,
        created: Date,
        publicNet: PublicNet,
        serverType: ServerType,
        datacenter: Datacenter,
        labels: [String: String],
        locked: Bool,
        protection: ServerProtection,
        backupWindow: String?,
        rescueEnabled: Bool,
        primaryDiskSize: Int,
        includedTraffic: Int64?,
        outgoingTraffic: Int64?,
        ingoingTraffic: Int64?
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.created = created
        self.publicNet = publicNet
        self.serverType = serverType
        self.datacenter = datacenter
        self.labels = labels
        self.locked = locked
        self.protection = protection
        self.backupWindow = backupWindow
        self.rescueEnabled = rescueEnabled
        self.primaryDiskSize = primaryDiskSize
        self.includedTraffic = includedTraffic
        self.outgoingTraffic = outgoingTraffic
        self.ingoingTraffic = ingoingTraffic
    }
}

/// Hetzner server lifecycle state. Unknown wire values (new states Hetzner
/// introduces later) decode to `.unknown` instead of throwing.
public enum ServerStatus: String, Codable, Sendable, Equatable {
    case running, initializing, starting, stopping, off, deleting, migrating, rebuilding
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ServerStatus(rawValue: raw) ?? .unknown
    }
}

public struct PublicNet: Codable, Sendable, Equatable {
    public let ipv4: PublicNetIPv4?
    public let ipv6: PublicNetIPv6?

    enum CodingKeys: String, CodingKey {
        case ipv4, ipv6
    }

    public init(ipv4: PublicNetIPv4?, ipv6: PublicNetIPv6?) {
        self.ipv4 = ipv4
        self.ipv6 = ipv6
    }
}

public struct PublicNetIPv4: Codable, Sendable, Equatable {
    public let ip: String

    enum CodingKeys: String, CodingKey { case ip }

    public init(ip: String) {
        self.ip = ip
    }
}

/// Hetzner's IPv6 assignment is a routed CIDR block, e.g. `"2001:db8::/64"`.
public struct PublicNetIPv6: Codable, Sendable, Equatable {
    public let ip: String

    enum CodingKeys: String, CodingKey { case ip }

    public init(ip: String) {
        self.ip = ip
    }
}

public struct ServerProtection: Codable, Sendable, Equatable {
    public let delete: Bool
    public let rebuild: Bool

    enum CodingKeys: String, CodingKey { case delete, rebuild }

    public init(delete: Bool, rebuild: Bool) {
        self.delete = delete
        self.rebuild = rebuild
    }
}

/// Wire envelope for `GET /servers/{id}` → `{"server": {...}}`.
struct ServerEnvelope: Decodable, Sendable {
    let server: Server
}
