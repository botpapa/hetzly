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
    /// `true`/`false` deprecation flag. Kept alongside the newer
    /// `deprecation` object (announcement/unavailability dates) added by
    /// the 2026 API — both are populated together on current responses, but
    /// older fixtures/responses only ever had this field.
    public let deprecated: Bool?
    public let prices: [ServerTypePrice]
    /// Server type grouping added by the 2026 API, e.g. `"cost_optimized"`,
    /// `"regular_purpose"`, `"dedicated_purpose"`. `nil` on older responses
    /// that don't send it.
    public let category: String?
    /// `"local"` or `"network"`, added by the 2026 API. `nil` on older
    /// responses that don't send it.
    public let storageType: String?
    /// Announcement/unavailability dates for a deprecated server type,
    /// added by the 2026 API. `nil` when not deprecated (or on older
    /// responses that only send the `deprecated` bool).
    public let deprecation: ServerTypeDeprecation?
    /// Per-location availability, added by the 2026 API. `nil` on older
    /// responses that don't send it.
    public let locations: [ServerTypeLocation]?

    enum CodingKeys: String, CodingKey {
        case id, name, description, cores, memory, disk
        case cpuType = "cpu_type"
        case architecture, deprecated, prices, category
        case storageType = "storage_type"
        case deprecation, locations
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
        prices: [ServerTypePrice],
        category: String? = nil,
        storageType: String? = nil,
        deprecation: ServerTypeDeprecation? = nil,
        locations: [ServerTypeLocation]? = nil
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
        self.category = category
        self.storageType = storageType
        self.deprecation = deprecation
        self.locations = locations
    }
}

/// `server_type.deprecation` object added by the 2026 API — distinct from
/// `ISODeprecation`'s identical shape (kept separate to avoid coupling two
/// otherwise-unrelated resource types to the same wire type).
public struct ServerTypeDeprecation: Codable, Sendable, Equatable {
    public let announced: Date
    public let unavailableAfter: Date

    enum CodingKeys: String, CodingKey {
        case announced
        case unavailableAfter = "unavailable_after"
    }

    public init(announced: Date, unavailableAfter: Date) {
        self.announced = announced
        self.unavailableAfter = unavailableAfter
    }
}

/// One entry of `server_type.locations`, added by the 2026 API: whether a
/// server type is currently orderable/recommended at a given location, and
/// that location's own deprecation window if it's being phased out there.
public struct ServerTypeLocation: Codable, Sendable, Equatable {
    public let id: Int
    public let name: String
    public let available: Bool
    public let recommended: Bool
    public let deprecation: ServerTypeDeprecation?

    enum CodingKeys: String, CodingKey {
        case id, name, available, recommended, deprecation
    }

    public init(id: Int, name: String, available: Bool, recommended: Bool, deprecation: ServerTypeDeprecation?) {
        self.id = id
        self.name = name
        self.available = available
        self.recommended = recommended
        self.deprecation = deprecation
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
