import Foundation

/// Connection status of a single server on a vSwitch (`server[].status` in
/// `GET /vswitch/{id}`). Connecting/disconnecting a server takes processing
/// time on Robot's side, so `.inProcess` is expected transiently right
/// after `RobotClient.addVSwitchServers`/`removeVSwitchServers` — Robot has
/// been observed to emit `"processing"` as a wire alias for `"in process"`;
/// both decode to `.inProcess`.
public enum RobotVSwitchConnectionStatus: String, Sendable, Equatable {
    case ready
    case inProcess = "in process"
    case failed
    case unknown

    fileprivate init(wireValue raw: String) {
        switch raw {
        case "ready": self = .ready
        case "in process", "processing": self = .inProcess
        case "failed": self = .failed
        default: self = .unknown
        }
    }
}

extension RobotVSwitchConnectionStatus: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RobotVSwitchConnectionStatus(wireValue: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// One server connected (or connecting/disconnecting) to a vSwitch, as
/// embedded in `RobotVSwitch.servers` (the `server[]` array of
/// `GET /vswitch/{id}`'s detail shape).
public struct RobotVSwitchServer: Codable, Sendable, Identifiable, Equatable {
    public var id: Int { serverNumber }

    public let serverNumber: Int
    public let serverIP: String?
    public let serverIPv6Net: String?
    public let status: RobotVSwitchConnectionStatus

    enum CodingKeys: String, CodingKey {
        case serverNumber = "server_number"
        case serverIP = "server_ip"
        case serverIPv6Net = "server_ipv6_net"
        case status
    }

    public init(serverNumber: Int, serverIP: String? = nil, serverIPv6Net: String? = nil, status: RobotVSwitchConnectionStatus) {
        self.serverNumber = serverNumber
        self.serverIP = serverIP
        self.serverIPv6Net = serverIPv6Net
        self.status = status
    }
}

/// A subnet routed over a vSwitch (`subnet[]` in `GET /vswitch/{id}`'s
/// detail shape). `mask` is kept as a `String` — Robot has been observed to
/// send it as either a JSON string or a bare JSON number depending on
/// endpoint/version, so decoding tolerates both (mirrors `RobotStringOrIntID`
/// used elsewhere in this client for the same reason).
public struct RobotVSwitchSubnet: Codable, Sendable, Equatable {
    public let ip: String
    public let mask: String

    enum CodingKeys: String, CodingKey { case ip, mask }

    public init(ip: String, mask: String) {
        self.ip = ip
        self.mask = mask
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ip = try container.decode(String.self, forKey: .ip)
        mask = try container.decode(RobotStringOrIntID.self, forKey: .mask).value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ip, forKey: .ip)
        try container.encode(mask, forKey: .mask)
    }
}

/// A Hetzner Cloud Network connected to a vSwitch (`cloud_network[]` in
/// `GET /vswitch/{id}`'s detail shape) — the bridge between a Robot
/// dedicated server's vSwitch and a Cloud project's private network.
public struct RobotCloudNetwork: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let ip: String
    public let mask: String

    enum CodingKeys: String, CodingKey { case id, ip, mask }

    public init(id: Int, ip: String, mask: String) {
        self.id = id
        self.ip = ip
        self.mask = mask
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        ip = try container.decode(String.self, forKey: .ip)
        mask = try container.decode(RobotStringOrIntID.self, forKey: .mask).value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(ip, forKey: .ip)
        try container.encode(mask, forKey: .mask)
    }
}

/// A Robot vSwitch — a VLAN Robot dedicated servers (and, via
/// `cloudNetworks`, Cloud private networks) can be bridged onto.
///
/// Robot's vSwitch endpoints return two different shapes of this same
/// resource depending on which endpoint answered:
/// - **List shape** (`GET /vswitch`, and the response to `POST /vswitch`
///   creating a brand-new vSwitch): only `id`/`name`/`vlan`/`cancelled` —
///   `server`/`subnet`/`cloud_network` are entirely absent from the JSON.
/// - **Detail shape** (`GET /vswitch/{id}`): the same four fields plus
///   populated `server`/`subnet`/`cloud_network` arrays.
///
/// This single model decodes both: the three nested-array fields default to
/// `[]` when their key is missing from the response, rather than failing
/// the decode. Encoding always emits all seven keys.
public struct RobotVSwitch: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let vlan: Int
    public let cancelled: Bool
    public let servers: [RobotVSwitchServer]
    public let subnets: [RobotVSwitchSubnet]
    public let cloudNetworks: [RobotCloudNetwork]

    enum CodingKeys: String, CodingKey {
        case id, name, vlan, cancelled
        case servers = "server"
        case subnets = "subnet"
        case cloudNetworks = "cloud_network"
    }

    public init(
        id: Int,
        name: String,
        vlan: Int,
        cancelled: Bool,
        servers: [RobotVSwitchServer] = [],
        subnets: [RobotVSwitchSubnet] = [],
        cloudNetworks: [RobotCloudNetwork] = []
    ) {
        self.id = id
        self.name = name
        self.vlan = vlan
        self.cancelled = cancelled
        self.servers = servers
        self.subnets = subnets
        self.cloudNetworks = cloudNetworks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        vlan = try container.decode(Int.self, forKey: .vlan)
        cancelled = try container.decodeIfPresent(Bool.self, forKey: .cancelled) ?? false
        servers = try container.decodeIfPresent([RobotVSwitchServer].self, forKey: .servers) ?? []
        subnets = try container.decodeIfPresent([RobotVSwitchSubnet].self, forKey: .subnets) ?? []
        cloudNetworks = try container.decodeIfPresent([RobotCloudNetwork].self, forKey: .cloudNetworks) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(vlan, forKey: .vlan)
        try container.encode(cancelled, forKey: .cancelled)
        try container.encode(servers, forKey: .servers)
        try container.encode(subnets, forKey: .subnets)
        try container.encode(cloudNetworks, forKey: .cloudNetworks)
    }
}
