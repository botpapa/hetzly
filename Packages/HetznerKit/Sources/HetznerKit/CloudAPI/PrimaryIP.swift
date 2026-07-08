import Foundation

/// `ipv4`/`ipv6` address family shared by `PrimaryIP.type` and
/// `FloatingIP.type`. Unknown wire values decode to `.unknown` instead of
/// throwing.
public enum IPAddressType: String, Codable, Sendable, Equatable {
    case ipv4, ipv6
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = IPAddressType(rawValue: raw) ?? .unknown
    }
}

/// One `{ip, dns_ptr}` reverse-DNS entry — shared wire shape between
/// `PrimaryIP.dnsPtr` and `FloatingIP.dnsPtr`.
public struct DNSPtrEntry: Codable, Sendable, Equatable {
    public let ip: String
    public let dnsPtr: String?

    enum CodingKeys: String, CodingKey {
        case ip
        case dnsPtr = "dns_ptr"
    }

    public init(ip: String, dnsPtr: String?) {
        self.ip = ip
        self.dnsPtr = dnsPtr
    }
}

/// `{delete: Bool}` protection shape shared by `PrimaryIP` and `FloatingIP`
/// (distinct from `ServerProtection`/`VolumeProtection`, which carry other
/// fields).
public struct DeleteProtection: Codable, Sendable, Equatable {
    public let delete: Bool

    enum CodingKeys: String, CodingKey { case delete }

    public init(delete: Bool) {
        self.delete = delete
    }
}

/// A Hetzner Cloud Primary IP — the (usually auto-created) IP a server is
/// reachable at, which can also be created standalone and assigned later.
public struct PrimaryIP: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let ip: String
    public let type: IPAddressType
    public let assigneeID: Int?
    public let assigneeType: String?
    public let autoDelete: Bool
    public let blocked: Bool
    public let created: Date
    public let datacenter: Datacenter
    public let dnsPtr: [DNSPtrEntry]
    public let labels: [String: String]
    public let protection: DeleteProtection

    enum CodingKeys: String, CodingKey {
        case id, name, ip, type
        case assigneeID = "assignee_id"
        case assigneeType = "assignee_type"
        case autoDelete = "auto_delete"
        case blocked, created, datacenter
        case dnsPtr = "dns_ptr"
        case labels, protection
    }

    public init(
        id: Int,
        name: String,
        ip: String,
        type: IPAddressType,
        assigneeID: Int?,
        assigneeType: String?,
        autoDelete: Bool,
        blocked: Bool,
        created: Date,
        datacenter: Datacenter,
        dnsPtr: [DNSPtrEntry],
        labels: [String: String],
        protection: DeleteProtection
    ) {
        self.id = id
        self.name = name
        self.ip = ip
        self.type = type
        self.assigneeID = assigneeID
        self.assigneeType = assigneeType
        self.autoDelete = autoDelete
        self.blocked = blocked
        self.created = created
        self.datacenter = datacenter
        self.dnsPtr = dnsPtr
        self.labels = labels
        self.protection = protection
    }
}

/// Wire envelope for `GET /primary_ips/{id}` and `PUT` responses.
struct PrimaryIPEnvelope: Decodable, Sendable {
    let primaryIP: PrimaryIP

    enum CodingKeys: String, CodingKey { case primaryIP = "primary_ip" }
}

/// Wire envelope for `POST /primary_ips` →
/// `{"primary_ip": ..., "action": ...}`. `action` is present when the IP was
/// created with an `assignee_id` (queues an implicit assignment); absent for
/// standalone creation.
struct CreatePrimaryIPResponseEnvelope: Decodable, Sendable {
    let primaryIP: PrimaryIP
    let action: Action?

    enum CodingKeys: String, CodingKey {
        case primaryIP = "primary_ip"
        case action
    }
}

/// Result of `CloudClient.createPrimaryIP`.
public struct CreatedPrimaryIP: Sendable, Equatable {
    public let primaryIP: PrimaryIP
    public let action: Action?

    public init(primaryIP: PrimaryIP, action: Action?) {
        self.primaryIP = primaryIP
        self.action = action
    }
}
