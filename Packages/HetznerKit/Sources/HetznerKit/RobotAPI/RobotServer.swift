import Foundation

/// A Hetzner Robot (dedicated server) provisioning state, as reported by
/// `GET /server`. Unlike Cloud servers, "off" isn't distinguishable here —
/// Robot only reports whether provisioning has finished.
public enum RobotServerStatus: String, Codable, Sendable, Equatable {
    case ready
    case inProcess = "in process"
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RobotServerStatus(rawValue: raw) ?? .unknown
    }
}

/// A lightweight subnet reference embedded directly on `RobotServer`. The
/// fuller standalone resource (with `server_number`/`gateway`) is
/// `RobotSubnet`, returned by `GET /subnet`.
public struct RobotServerSubnet: Codable, Sendable, Equatable {
    public let ip: String
    public let mask: String

    enum CodingKeys: String, CodingKey { case ip, mask }

    public init(ip: String, mask: String) {
        self.ip = ip
        self.mask = mask
    }
}

/// A Hetzner Robot dedicated server, from `GET /server` (list, wrapped as
/// `[{"server": {...}}]`) and `GET /server/{n}` (single, wrapped as
/// `{"server": {...}}`).
public struct RobotServer: Codable, Sendable, Identifiable, Equatable {
    public var id: Int { serverNumber }

    public let serverIP: String?
    public let serverIPv6Net: String?
    public let serverNumber: Int
    public let serverName: String
    public let product: String
    public let dc: String
    public let traffic: String
    public let status: RobotServerStatus
    public let cancelled: Bool
    /// Raw wire value (e.g. `"2024-12-31"`); Robot doesn't emit a full
    /// timestamp here, so this is left as a plain string rather than parsed.
    public let paidUntil: String?
    public let ip: [String]?
    public let subnet: [RobotServerSubnet]?

    enum CodingKeys: String, CodingKey {
        case serverIP = "server_ip"
        case serverIPv6Net = "server_ipv6_net"
        case serverNumber = "server_number"
        case serverName = "server_name"
        case product, dc, traffic, status, cancelled
        case paidUntil = "paid_until"
        case ip, subnet
    }

    public init(
        serverIP: String?,
        serverIPv6Net: String?,
        serverNumber: Int,
        serverName: String,
        product: String,
        dc: String,
        traffic: String,
        status: RobotServerStatus,
        cancelled: Bool,
        paidUntil: String?,
        ip: [String]?,
        subnet: [RobotServerSubnet]?
    ) {
        self.serverIP = serverIP
        self.serverIPv6Net = serverIPv6Net
        self.serverNumber = serverNumber
        self.serverName = serverName
        self.product = product
        self.dc = dc
        self.traffic = traffic
        self.status = status
        self.cancelled = cancelled
        self.paidUntil = paidUntil
        self.ip = ip
        self.subnet = subnet
    }
}
