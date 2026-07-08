import Foundation

/// A Hetzner Cloud Load Balancer.
public struct LoadBalancer: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let publicNet: LBPublicNet
    public let privateNet: [LBPrivateNet]
    public let location: Location
    public let loadBalancerType: LoadBalancerType
    public let protection: LBProtection
    public let labels: [String: String]
    public let created: Date
    public let services: [LBService]
    public let targets: [LBTarget]
    public let algorithm: LBAlgorithm
    public let outgoingTraffic: Int64?
    public let ingoingTraffic: Int64?
    public let includedTraffic: Int64?

    enum CodingKeys: String, CodingKey {
        case id, name
        case publicNet = "public_net"
        case privateNet = "private_net"
        case location
        case loadBalancerType = "load_balancer_type"
        case protection, labels, created, services, targets, algorithm
        case outgoingTraffic = "outgoing_traffic"
        case ingoingTraffic = "ingoing_traffic"
        case includedTraffic = "included_traffic"
    }

    public init(
        id: Int,
        name: String,
        publicNet: LBPublicNet,
        privateNet: [LBPrivateNet],
        location: Location,
        loadBalancerType: LoadBalancerType,
        protection: LBProtection,
        labels: [String: String],
        created: Date,
        services: [LBService],
        targets: [LBTarget],
        algorithm: LBAlgorithm,
        outgoingTraffic: Int64?,
        ingoingTraffic: Int64?,
        includedTraffic: Int64?
    ) {
        self.id = id
        self.name = name
        self.publicNet = publicNet
        self.privateNet = privateNet
        self.location = location
        self.loadBalancerType = loadBalancerType
        self.protection = protection
        self.labels = labels
        self.created = created
        self.services = services
        self.targets = targets
        self.algorithm = algorithm
        self.outgoingTraffic = outgoingTraffic
        self.ingoingTraffic = ingoingTraffic
        self.includedTraffic = includedTraffic
    }
}

public struct LBProtection: Codable, Sendable, Equatable {
    public let delete: Bool

    enum CodingKeys: String, CodingKey { case delete }

    public init(delete: Bool) {
        self.delete = delete
    }
}

// MARK: - Networking

public struct LBPublicNet: Codable, Sendable, Equatable {
    public let enabled: Bool
    public let ipv4: LBPublicNetIPv4?
    public let ipv6: LBPublicNetIPv6?

    enum CodingKeys: String, CodingKey { case enabled, ipv4, ipv6 }

    public init(enabled: Bool, ipv4: LBPublicNetIPv4?, ipv6: LBPublicNetIPv6?) {
        self.enabled = enabled
        self.ipv4 = ipv4
        self.ipv6 = ipv6
    }
}

public struct LBPublicNetIPv4: Codable, Sendable, Equatable {
    public let ip: String?
    public let dnsPtr: String?

    enum CodingKeys: String, CodingKey {
        case ip
        case dnsPtr = "dns_ptr"
    }

    public init(ip: String?, dnsPtr: String?) {
        self.ip = ip
        self.dnsPtr = dnsPtr
    }
}

public struct LBPublicNetIPv6: Codable, Sendable, Equatable {
    public let ip: String?
    public let dnsPtr: String?

    enum CodingKeys: String, CodingKey {
        case ip
        case dnsPtr = "dns_ptr"
    }

    public init(ip: String?, dnsPtr: String?) {
        self.ip = ip
        self.dnsPtr = dnsPtr
    }
}

public struct LBPrivateNet: Codable, Sendable, Equatable {
    public let network: Int
    public let ip: String

    enum CodingKeys: String, CodingKey { case network, ip }

    public init(network: Int, ip: String) {
        self.network = network
        self.ip = ip
    }
}

// MARK: - Algorithm

public struct LBAlgorithm: Codable, Sendable, Equatable {
    public let type: LBAlgorithmType

    enum CodingKeys: String, CodingKey { case type }

    public init(type: LBAlgorithmType) {
        self.type = type
    }
}

/// Unknown wire values decode to `.unknown` instead of throwing.
public enum LBAlgorithmType: String, Codable, Sendable, Equatable {
    case roundRobin = "round_robin"
    case leastConnections = "least_connections"
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LBAlgorithmType(rawValue: raw) ?? .unknown
    }
}

// MARK: - Load balancer type (catalog)

public struct LoadBalancerType: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let description: String
    public let maxConnections: Int?
    public let maxServices: Int?
    public let maxTargets: Int?
    public let prices: [ServerTypePrice]

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case maxConnections = "max_connections"
        case maxServices = "max_services"
        case maxTargets = "max_targets"
        case prices
    }

    public init(
        id: Int,
        name: String,
        description: String,
        maxConnections: Int?,
        maxServices: Int?,
        maxTargets: Int?,
        prices: [ServerTypePrice]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.maxConnections = maxConnections
        self.maxServices = maxServices
        self.maxTargets = maxTargets
        self.prices = prices
    }
}

// MARK: - Services

public struct LBService: Codable, Sendable, Equatable {
    public let `protocol`: LBServiceProtocol
    public let listenPort: Int
    public let destinationPort: Int
    public let proxyprotocol: Bool
    public let http: LBServiceHTTP?
    public let healthCheck: LBHealthCheck?

    enum CodingKeys: String, CodingKey {
        case `protocol`
        case listenPort = "listen_port"
        case destinationPort = "destination_port"
        case proxyprotocol
        case http
        case healthCheck = "health_check"
    }

    public init(
        protocol: LBServiceProtocol,
        listenPort: Int,
        destinationPort: Int,
        proxyprotocol: Bool,
        http: LBServiceHTTP?,
        healthCheck: LBHealthCheck?
    ) {
        self.protocol = `protocol`
        self.listenPort = listenPort
        self.destinationPort = destinationPort
        self.proxyprotocol = proxyprotocol
        self.http = http
        self.healthCheck = healthCheck
    }
}

/// Unknown wire values decode to `.unknown` instead of throwing.
public enum LBServiceProtocol: String, Codable, Sendable, Equatable {
    case tcp, http, https
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LBServiceProtocol(rawValue: raw) ?? .unknown
    }
}

public struct LBServiceHTTP: Codable, Sendable, Equatable {
    public let cookieName: String?
    public let cookieLifetime: Int?
    public let certificates: [Int]
    public let redirectHTTP: Bool?
    public let stickySessions: Bool?

    enum CodingKeys: String, CodingKey {
        case cookieName = "cookie_name"
        case cookieLifetime = "cookie_lifetime"
        case certificates
        case redirectHTTP = "redirect_http"
        case stickySessions = "sticky_sessions"
    }

    public init(
        cookieName: String?,
        cookieLifetime: Int?,
        certificates: [Int],
        redirectHTTP: Bool?,
        stickySessions: Bool?
    ) {
        self.cookieName = cookieName
        self.cookieLifetime = cookieLifetime
        self.certificates = certificates
        self.redirectHTTP = redirectHTTP
        self.stickySessions = stickySessions
    }
}

public struct LBHealthCheck: Codable, Sendable, Equatable {
    public let `protocol`: LBServiceProtocol
    public let port: Int
    public let interval: Int
    public let timeout: Int
    public let retries: Int
    public let http: LBHealthCheckHTTP?

    enum CodingKeys: String, CodingKey {
        case `protocol`, port, interval, timeout, retries, http
    }

    public init(
        protocol: LBServiceProtocol,
        port: Int,
        interval: Int,
        timeout: Int,
        retries: Int,
        http: LBHealthCheckHTTP?
    ) {
        self.protocol = `protocol`
        self.port = port
        self.interval = interval
        self.timeout = timeout
        self.retries = retries
        self.http = http
    }
}

public struct LBHealthCheckHTTP: Codable, Sendable, Equatable {
    public let domain: String?
    public let path: String
    public let response: String?
    public let statusCodes: [String]?
    public let tls: Bool?

    enum CodingKeys: String, CodingKey {
        case domain, path, response
        case statusCodes = "status_codes"
        case tls
    }

    public init(domain: String?, path: String, response: String?, statusCodes: [String]?, tls: Bool?) {
        self.domain = domain
        self.path = path
        self.response = response
        self.statusCodes = statusCodes
        self.tls = tls
    }
}

// MARK: - Targets

public struct LBTarget: Codable, Sendable, Equatable {
    public let type: LBTargetType
    public let server: LBTargetServer?
    public let labelSelector: LBTargetLabelSelector?
    public let ip: LBTargetIP?
    public let usePrivateIP: Bool?
    public let healthStatus: [LBTargetHealthStatus]?

    enum CodingKeys: String, CodingKey {
        case type, server
        case labelSelector = "label_selector"
        case ip
        case usePrivateIP = "use_private_ip"
        case healthStatus = "health_status"
    }

    public init(
        type: LBTargetType,
        server: LBTargetServer?,
        labelSelector: LBTargetLabelSelector?,
        ip: LBTargetIP?,
        usePrivateIP: Bool?,
        healthStatus: [LBTargetHealthStatus]?
    ) {
        self.type = type
        self.server = server
        self.labelSelector = labelSelector
        self.ip = ip
        self.usePrivateIP = usePrivateIP
        self.healthStatus = healthStatus
    }
}

/// Unknown wire values decode to `.unknown` instead of throwing.
public enum LBTargetType: String, Codable, Sendable, Equatable {
    case server
    case labelSelector = "label_selector"
    case ip
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LBTargetType(rawValue: raw) ?? .unknown
    }
}

public struct LBTargetServer: Codable, Sendable, Equatable {
    public let id: Int

    enum CodingKeys: String, CodingKey { case id }

    public init(id: Int) {
        self.id = id
    }
}

public struct LBTargetLabelSelector: Codable, Sendable, Equatable {
    public let selector: String

    enum CodingKeys: String, CodingKey { case selector }

    public init(selector: String) {
        self.selector = selector
    }
}

public struct LBTargetIP: Codable, Sendable, Equatable {
    public let ip: String

    enum CodingKeys: String, CodingKey { case ip }

    public init(ip: String) {
        self.ip = ip
    }
}

public struct LBTargetHealthStatus: Codable, Sendable, Equatable {
    public let listenPort: Int
    public let status: LBTargetHealthState

    enum CodingKeys: String, CodingKey {
        case listenPort = "listen_port"
        case status
    }

    public init(listenPort: Int, status: LBTargetHealthState) {
        self.listenPort = listenPort
        self.status = status
    }
}

/// Unknown wire values decode to `.unknown` instead of throwing.
public enum LBTargetHealthState: String, Codable, Sendable, Equatable {
    case healthy, unhealthy, unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LBTargetHealthState(rawValue: raw) ?? .unknown
    }
}

// MARK: - Envelopes

/// Wire envelope for `GET /load_balancers/{id}` → `{"load_balancer": {...}}`.
struct LoadBalancerEnvelope: Decodable, Sendable {
    let loadBalancer: LoadBalancer

    enum CodingKeys: String, CodingKey {
        case loadBalancer = "load_balancer"
    }
}

/// Result of `POST /load_balancers`: the new load balancer plus the queued
/// creation action (`nil` if Hetzner ever returns it inline-complete).
public struct CreatedLoadBalancer: Sendable, Equatable {
    public let loadBalancer: LoadBalancer
    public let action: Action?

    public init(loadBalancer: LoadBalancer, action: Action?) {
        self.loadBalancer = loadBalancer
        self.action = action
    }
}

struct CreateLoadBalancerResponseEnvelope: Decodable, Sendable {
    let loadBalancer: LoadBalancer
    let action: Action?

    enum CodingKeys: String, CodingKey {
        case loadBalancer = "load_balancer"
        case action
    }
}
