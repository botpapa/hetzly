import Foundation

/// A Hetzner Cloud Floating IP — a standalone IP that can be re-assigned
/// between servers within the same location.
public struct FloatingIP: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let description: String?
    public let ip: String
    public let type: IPAddressType
    public let server: Int?
    public let dnsPtr: [DNSPtrEntry]
    public let homeLocation: Location
    public let blocked: Bool
    public let protection: DeleteProtection
    public let labels: [String: String]
    public let created: Date

    enum CodingKeys: String, CodingKey {
        case id, name, description, ip, type, server
        case dnsPtr = "dns_ptr"
        case homeLocation = "home_location"
        case blocked, protection, labels, created
    }

    public init(
        id: Int,
        name: String,
        description: String?,
        ip: String,
        type: IPAddressType,
        server: Int?,
        dnsPtr: [DNSPtrEntry],
        homeLocation: Location,
        blocked: Bool,
        protection: DeleteProtection,
        labels: [String: String],
        created: Date
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.ip = ip
        self.type = type
        self.server = server
        self.dnsPtr = dnsPtr
        self.homeLocation = homeLocation
        self.blocked = blocked
        self.protection = protection
        self.labels = labels
        self.created = created
    }

    /// Labels decode leniently — see `decodeLenientLabels`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        ip = try container.decode(String.self, forKey: .ip)
        type = try container.decode(IPAddressType.self, forKey: .type)
        server = try container.decodeIfPresent(Int.self, forKey: .server)
        dnsPtr = try container.decode([DNSPtrEntry].self, forKey: .dnsPtr)
        homeLocation = try container.decode(Location.self, forKey: .homeLocation)
        blocked = try container.decode(Bool.self, forKey: .blocked)
        protection = try container.decode(DeleteProtection.self, forKey: .protection)
        labels = try container.decodeLenientLabels(forKey: .labels)
        created = try container.decode(Date.self, forKey: .created)
    }
}

/// Wire envelope for `GET /floating_ips/{id}` and `PUT` responses.
struct FloatingIPEnvelope: Decodable, Sendable {
    let floatingIP: FloatingIP

    enum CodingKeys: String, CodingKey { case floatingIP = "floating_ip" }
}

/// Wire envelope for `POST /floating_ips` →
/// `{"floating_ip": ..., "action": ...}`. `action` is present when the IP
/// was created with a `server`; absent for standalone creation.
struct CreateFloatingIPResponseEnvelope: Decodable, Sendable {
    let floatingIP: FloatingIP
    let action: Action?

    enum CodingKeys: String, CodingKey {
        case floatingIP = "floating_ip"
        case action
    }
}

/// Result of `CloudClient.createFloatingIP`.
public struct CreatedFloatingIP: Sendable, Equatable {
    public let floatingIP: FloatingIP
    public let action: Action?

    public init(floatingIP: FloatingIP, action: Action?) {
        self.floatingIP = floatingIP
        self.action = action
    }
}
