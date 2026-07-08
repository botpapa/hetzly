import Foundation

public struct ServerType: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let description: String
    public let cores: Int
    /// RAM in GB.
    public let memory: Double
    /// Disk size in GB.
    public let disk: Int
    public let cpuType: CPUType
    public let architecture: Architecture
    public let deprecated: Bool?
    public let prices: [ServerTypePrice]

    enum CodingKeys: String, CodingKey {
        case id, name, description, cores, memory, disk
        case cpuType = "cpu_type"
        case architecture, deprecated, prices
    }

    public init(
        id: Int,
        name: String,
        description: String,
        cores: Int,
        memory: Double,
        disk: Int,
        cpuType: CPUType,
        architecture: Architecture,
        deprecated: Bool?,
        prices: [ServerTypePrice]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.cores = cores
        self.memory = memory
        self.disk = disk
        self.cpuType = cpuType
        self.architecture = architecture
        self.deprecated = deprecated
        self.prices = prices
    }
}

/// Unknown wire values decode to `.unknown` instead of throwing.
public enum CPUType: String, Codable, Sendable, Equatable {
    case shared, dedicated
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CPUType(rawValue: raw) ?? .unknown
    }
}

/// Unknown wire values decode to `.unknown` instead of throwing.
public enum Architecture: String, Codable, Sendable, Equatable {
    case x86, arm
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Architecture(rawValue: raw) ?? .unknown
    }
}

/// A server type's price at one location. Shared by `ServerType.prices` and
/// the `/pricing` endpoint's `server_types`/`primary_ips` entries — both use
/// this exact `{location, price_hourly, price_monthly}` shape on the wire.
public struct ServerTypePrice: Codable, Sendable, Equatable {
    public let location: String
    public let hourly: PriceValue
    public let monthly: PriceValue

    enum CodingKeys: String, CodingKey {
        case location
        case hourly = "price_hourly"
        case monthly = "price_monthly"
    }

    public init(location: String, hourly: PriceValue, monthly: PriceValue) {
        self.location = location
        self.hourly = hourly
        self.monthly = monthly
    }
}

/// Hetzner reports prices as decimal strings (net/gross) to avoid float
/// rounding issues; `netDecimal` parses `net` for cost math.
public struct PriceValue: Codable, Sendable, Equatable {
    public let net: String
    public let gross: String

    enum CodingKeys: String, CodingKey { case net, gross }

    public init(net: String, gross: String) {
        self.net = net
        self.gross = gross
    }

    /// `net` parsed as `Decimal`; `nil` if Hetzner's string isn't a valid
    /// decimal literal.
    public var netDecimal: Decimal? {
        Decimal(string: net)
    }
}
