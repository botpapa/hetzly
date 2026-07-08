import Foundation

/// A Hetzner Cloud firewall: a set of rules applied to servers or
/// label-selected resources.
public struct Firewall: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let labels: [String: String]
    public let created: Date
    public let rules: [FirewallRule]
    public let appliedTo: [FirewallResource]

    enum CodingKeys: String, CodingKey {
        case id, name, labels, created, rules
        case appliedTo = "applied_to"
    }

    public init(
        id: Int,
        name: String,
        labels: [String: String],
        created: Date,
        rules: [FirewallRule],
        appliedTo: [FirewallResource]
    ) {
        self.id = id
        self.name = name
        self.labels = labels
        self.created = created
        self.rules = rules
        self.appliedTo = appliedTo
    }

    /// Labels decode leniently — see `decodeLenientLabels`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        labels = try container.decodeLenientLabels(forKey: .labels)
        created = try container.decode(Date.self, forKey: .created)
        rules = try container.decode([FirewallRule].self, forKey: .rules)
        appliedTo = try container.decode([FirewallResource].self, forKey: .appliedTo)
    }
}

/// Traffic direction a `FirewallRule` matches. Unknown wire values decode to
/// `.unknown` instead of throwing.
public enum FirewallDirection: String, Codable, Sendable, Equatable {
    case inbound = "in"
    case outbound = "out"
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FirewallDirection(rawValue: raw) ?? .unknown
    }
}

/// IP protocol a `FirewallRule` matches. Unknown wire values decode to
/// `.unknown` instead of throwing.
public enum FirewallProtocol: String, Codable, Sendable, Equatable {
    case tcp, udp, icmp, esp, gre
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FirewallProtocol(rawValue: raw) ?? .unknown
    }
}

/// A single firewall rule. Codable in both directions: decoded from
/// `GET /firewalls/{id}` responses and encoded again as part of the
/// `set_rules` / `create` request bodies.
///
/// `networkProtocol` maps to the wire key `"protocol"` — `protocol` is a
/// Swift keyword, so the property is named to avoid backtick-escaping at
/// every call site.
public struct FirewallRule: Codable, Sendable, Equatable {
    public let direction: FirewallDirection
    public let networkProtocol: FirewallProtocol
    /// A single port ("80") or range ("80-85"); `nil` for protocols without
    /// ports (icmp, esp, gre).
    public let port: String?
    public let sourceIPs: [String]
    public let destinationIPs: [String]
    public let description: String?

    enum CodingKeys: String, CodingKey {
        case direction
        case networkProtocol = "protocol"
        case port
        case sourceIPs = "source_ips"
        case destinationIPs = "destination_ips"
        case description
    }

    public init(
        direction: FirewallDirection,
        networkProtocol: FirewallProtocol,
        port: String?,
        sourceIPs: [String],
        destinationIPs: [String],
        description: String?
    ) {
        self.direction = direction
        self.networkProtocol = networkProtocol
        self.port = port
        self.sourceIPs = sourceIPs
        self.destinationIPs = destinationIPs
        self.description = description
    }
}

/// Which kind of resource a `FirewallResource` entry refers to. Unknown wire
/// values decode to `.unknown` instead of throwing.
public enum FirewallResourceType: String, Codable, Sendable, Equatable {
    case server
    case labelSelector = "label_selector"
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FirewallResourceType(rawValue: raw) ?? .unknown
    }
}

public struct FirewallResourceServerRef: Codable, Sendable, Equatable {
    public let id: Int

    enum CodingKeys: String, CodingKey { case id }

    public init(id: Int) {
        self.id = id
    }
}

public struct FirewallLabelSelectorRef: Codable, Sendable, Equatable {
    public let selector: String

    enum CodingKeys: String, CodingKey { case selector }

    public init(selector: String) {
        self.selector = selector
    }
}

/// A concrete resource a label selector expanded to — only present on
/// `FirewallResource.appliedToResources` when `type == .labelSelector`.
public struct FirewallAppliedToResource: Codable, Sendable, Equatable {
    public let type: FirewallResourceType
    public let server: FirewallResourceServerRef?

    enum CodingKeys: String, CodingKey { case type, server }

    public init(type: FirewallResourceType, server: FirewallResourceServerRef?) {
        self.type = type
        self.server = server
    }
}

/// One entry of `Firewall.appliedTo`.
public struct FirewallResource: Codable, Sendable, Equatable {
    public let type: FirewallResourceType
    public let server: FirewallResourceServerRef?
    public let labelSelector: FirewallLabelSelectorRef?
    public let appliedToResources: [FirewallAppliedToResource]?

    enum CodingKeys: String, CodingKey {
        case type, server
        case labelSelector = "label_selector"
        case appliedToResources = "applied_to_resources"
    }

    public init(
        type: FirewallResourceType,
        server: FirewallResourceServerRef?,
        labelSelector: FirewallLabelSelectorRef?,
        appliedToResources: [FirewallAppliedToResource]?
    ) {
        self.type = type
        self.server = server
        self.labelSelector = labelSelector
        self.appliedToResources = appliedToResources
    }
}

/// One `apply_to` / `apply_to_resources` / `remove_from_resources` target:
/// either a specific server or a label selector matching a dynamic set of
/// servers. Used only to build request bodies.
public enum FirewallApplyTarget: Sendable, Equatable {
    case server(id: Int)
    case labelSelector(String)

    var payload: FirewallApplyToPayload {
        switch self {
        case .server(let id):
            return FirewallApplyToPayload(type: "server", server: FirewallServerRefPayload(id: id), labelSelector: nil)
        case .labelSelector(let selector):
            return FirewallApplyToPayload(
                type: "label_selector",
                server: nil,
                labelSelector: FirewallLabelSelectorPayload(selector: selector)
            )
        }
    }
}

/// Wire envelope for `GET /firewalls/{id}` and `PUT` responses.
struct FirewallEnvelope: Decodable, Sendable {
    let firewall: Firewall
}

/// Wire envelope for `POST /firewalls` → `{"firewall": ..., "actions": [...]}`.
struct CreateFirewallResponseEnvelope: Decodable, Sendable {
    let firewall: Firewall
    let actions: [Action]
}

/// Wire envelope for firewall action endpoints (`set_rules`,
/// `apply_to_resources`, `remove_from_resources`), which return
/// `{"actions": [...]}` (plural) rather than the single-action
/// `{"action": ...}` envelope used elsewhere in the API.
struct FirewallActionsEnvelope: Decodable, Sendable {
    let actions: [Action]
}

/// Result of `CloudClient.createFirewall`.
public struct CreatedFirewall: Sendable, Equatable {
    public let firewall: Firewall
    public let actions: [Action]

    public init(firewall: Firewall, actions: [Action]) {
        self.firewall = firewall
        self.actions = actions
    }
}
