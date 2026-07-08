import Foundation

// MARK: - Wire-tolerant decoding helpers

/// Robot returns some fields as either a single string or an array of
/// strings depending on the endpoint (e.g. `dist`, `description`,
/// `location`). Decodes either shape into `[String]`.
struct RobotStringOrArray: Decodable, Sendable {
    let values: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let array = try? container.decode([String].self) {
            values = array
            return
        }
        if let single = try? container.decode(String.self) {
            values = single.isEmpty ? [] : [single]
            return
        }
        values = []
    }
}

/// Robot represents some product identifiers as JSON strings and others
/// (server market products) as JSON numbers. Decodes either into `String`.
struct RobotStringOrIntID: Decodable, Sendable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
            return
        }
        if let int = try? container.decode(Int.self) {
            value = String(int)
            return
        }
        let double = try container.decode(Double.self)
        value = String(double)
    }
}

// MARK: - Prices

/// Robot Webservice prices are net/gross decimal strings (never floats, to
/// avoid rounding surprises). `netDecimal`/`grossDecimal` parse them for
/// cost math; `nil` if Hetzner's string isn't a valid decimal literal.
public struct RobotPrice: Codable, Sendable, Equatable {
    public let net: String
    public let gross: String

    enum CodingKeys: String, CodingKey { case net, gross }

    public init(net: String, gross: String) {
        self.net = net
        self.gross = gross
    }

    public var netDecimal: Decimal? { Decimal(string: net) }
    public var grossDecimal: Decimal? { Decimal(string: gross) }
}

/// One location's pricing for a `RobotProduct`.
public struct RobotProductPrice: Codable, Sendable, Equatable {
    public let location: String
    public let price: RobotPrice
    public let priceSetup: RobotPrice
    public let priceHourly: RobotPrice?

    enum CodingKeys: String, CodingKey {
        case location, price
        case priceSetup = "price_setup"
        case priceHourly = "price_hourly"
    }

    public init(location: String, price: RobotPrice, priceSetup: RobotPrice, priceHourly: RobotPrice? = nil) {
        self.location = location
        self.price = price
        self.priceSetup = priceSetup
        self.priceHourly = priceHourly
    }
}

// MARK: - RobotProduct (GET /order/server/product)

/// A standard, always-orderable dedicated server product from
/// `GET /order/server/product`.
public struct RobotProduct: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let description: [String]
    public let traffic: String
    public let dist: [String]
    public let arch: [String]?
    public let lang: [String]?
    public let location: [String]
    public let prices: [RobotProductPrice]

    enum CodingKeys: String, CodingKey {
        case id, name, description, traffic, dist, arch, lang, location, prices
    }

    public init(
        id: String,
        name: String,
        description: [String],
        traffic: String,
        dist: [String],
        arch: [String]? = nil,
        lang: [String]? = nil,
        location: [String],
        prices: [RobotProductPrice]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.traffic = traffic
        self.dist = dist
        self.arch = arch
        self.lang = lang
        self.location = location
        self.prices = prices
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(RobotStringOrIntID.self, forKey: .id).value
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(RobotStringOrArray.self, forKey: .description)?.values ?? []
        traffic = try container.decodeIfPresent(String.self, forKey: .traffic) ?? ""
        dist = try container.decodeIfPresent(RobotStringOrArray.self, forKey: .dist)?.values ?? []
        arch = try container.decodeIfPresent(RobotStringOrArray.self, forKey: .arch)?.values
        lang = try container.decodeIfPresent(RobotStringOrArray.self, forKey: .lang)?.values
        location = try container.decodeIfPresent(RobotStringOrArray.self, forKey: .location)?.values ?? []
        prices = try container.decodeIfPresent([RobotProductPrice].self, forKey: .prices) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(traffic, forKey: .traffic)
        try container.encode(dist, forKey: .dist)
        try container.encodeIfPresent(arch, forKey: .arch)
        try container.encodeIfPresent(lang, forKey: .lang)
        try container.encode(location, forKey: .location)
        try container.encode(prices, forKey: .prices)
    }
}

/// Wire envelope for `GET /order/server/product[/{id}]` → `{"product": {...}}`
/// (each element of a list response is individually wrapped this way too).
struct RobotProductEnvelope: Decodable, Sendable {
    let product: RobotProduct
}

// MARK: - RobotMarketProduct (GET /order/server_market/product)

/// An auction ("server market") dedicated server offer from
/// `GET /order/server_market/product`. Decoded defensively — unknown or
/// missing auxiliary fields never cause the whole product to fail to decode.
public struct RobotMarketProduct: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let description: [String]
    public let traffic: String
    public let dist: [String]
    public let cpu: String
    public let cpuBenchmark: Int?
    /// RAM in GB.
    public let memorySize: Int
    /// Disk size in GB.
    public let hddSize: Int
    public let hddText: String?
    public let hddCount: Int?
    public let datacenter: String?
    public let networkSpeed: String?
    /// Net price, as a decimal string.
    public let price: String
    /// One-time setup fee, as a decimal string.
    public let priceSetup: String
    public let priceVAT: String?
    public let fixedPrice: Bool?
    public let nextReduce: Int?
    public let nextReduceDate: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, traffic, dist, cpu
        case cpuBenchmark = "cpu_benchmark"
        case memorySize = "memory_size"
        case hddSize = "hdd_size"
        case hddText = "hdd_text"
        case hddCount = "hdd_count"
        case datacenter
        case networkSpeed = "network_speed"
        case price
        case priceSetup = "price_setup"
        case priceVAT = "price_vat"
        case fixedPrice = "fixed_price"
        case nextReduce = "next_reduce"
        case nextReduceDate = "next_reduce_date"
    }

    public init(
        id: String,
        name: String,
        description: [String],
        traffic: String,
        dist: [String],
        cpu: String,
        cpuBenchmark: Int? = nil,
        memorySize: Int,
        hddSize: Int,
        hddText: String? = nil,
        hddCount: Int? = nil,
        datacenter: String? = nil,
        networkSpeed: String? = nil,
        price: String,
        priceSetup: String,
        priceVAT: String? = nil,
        fixedPrice: Bool? = nil,
        nextReduce: Int? = nil,
        nextReduceDate: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.traffic = traffic
        self.dist = dist
        self.cpu = cpu
        self.cpuBenchmark = cpuBenchmark
        self.memorySize = memorySize
        self.hddSize = hddSize
        self.hddText = hddText
        self.hddCount = hddCount
        self.datacenter = datacenter
        self.networkSpeed = networkSpeed
        self.price = price
        self.priceSetup = priceSetup
        self.priceVAT = priceVAT
        self.fixedPrice = fixedPrice
        self.nextReduce = nextReduce
        self.nextReduceDate = nextReduceDate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(RobotStringOrIntID.self, forKey: .id).value
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try container.decodeIfPresent(RobotStringOrArray.self, forKey: .description)?.values ?? []
        traffic = try container.decodeIfPresent(String.self, forKey: .traffic) ?? ""
        dist = try container.decodeIfPresent(RobotStringOrArray.self, forKey: .dist)?.values ?? []
        cpu = try container.decodeIfPresent(String.self, forKey: .cpu) ?? ""
        cpuBenchmark = try? container.decodeIfPresent(Int.self, forKey: .cpuBenchmark)
        memorySize = try container.decodeIfPresent(Int.self, forKey: .memorySize) ?? 0
        hddSize = try container.decodeIfPresent(Int.self, forKey: .hddSize) ?? 0
        hddText = try? container.decodeIfPresent(String.self, forKey: .hddText)
        hddCount = try? container.decodeIfPresent(Int.self, forKey: .hddCount)
        datacenter = try? container.decodeIfPresent(String.self, forKey: .datacenter)
        networkSpeed = try? container.decodeIfPresent(String.self, forKey: .networkSpeed)
        price = try container.decodeIfPresent(String.self, forKey: .price) ?? "0"
        priceSetup = try container.decodeIfPresent(String.self, forKey: .priceSetup) ?? "0"
        priceVAT = try? container.decodeIfPresent(String.self, forKey: .priceVAT)
        fixedPrice = try? container.decodeIfPresent(Bool.self, forKey: .fixedPrice)
        nextReduce = try? container.decodeIfPresent(Int.self, forKey: .nextReduce)
        nextReduceDate = try? container.decodeIfPresent(String.self, forKey: .nextReduceDate)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(traffic, forKey: .traffic)
        try container.encode(dist, forKey: .dist)
        try container.encode(cpu, forKey: .cpu)
        try container.encodeIfPresent(cpuBenchmark, forKey: .cpuBenchmark)
        try container.encode(memorySize, forKey: .memorySize)
        try container.encode(hddSize, forKey: .hddSize)
        try container.encodeIfPresent(hddText, forKey: .hddText)
        try container.encodeIfPresent(hddCount, forKey: .hddCount)
        try container.encodeIfPresent(datacenter, forKey: .datacenter)
        try container.encodeIfPresent(networkSpeed, forKey: .networkSpeed)
        try container.encode(price, forKey: .price)
        try container.encode(priceSetup, forKey: .priceSetup)
        try container.encodeIfPresent(priceVAT, forKey: .priceVAT)
        try container.encodeIfPresent(fixedPrice, forKey: .fixedPrice)
        try container.encodeIfPresent(nextReduce, forKey: .nextReduce)
        try container.encodeIfPresent(nextReduceDate, forKey: .nextReduceDate)
    }

    /// `price` parsed as `Decimal`; `nil` if not a valid decimal literal.
    public var priceDecimal: Decimal? { Decimal(string: price) }
    /// `priceSetup` parsed as `Decimal`; `nil` if not a valid decimal literal.
    public var priceSetupDecimal: Decimal? { Decimal(string: priceSetup) }
}

/// Wire envelope for `GET /order/server_market/product[/{id}]` →
/// `{"product": {...}}`.
struct RobotMarketProductEnvelope: Decodable, Sendable {
    let product: RobotMarketProduct
}

// MARK: - Orders (form-encoded POST bodies)

/// A standard dedicated server order (`POST /order/server`).
///
/// `test` defaults to `true` — a safety net so a caller that forgets to set
/// it never accidentally places a real order. UI flows placing a real order
/// MUST explicitly pass `test: false`.
public struct RobotServerOrder: Sendable, Equatable {
    public let productID: String
    public let location: String?
    public let dist: String?
    /// SSH key fingerprints to authorize on the new server.
    public let authorizedKeys: [String]
    public let test: Bool

    public init(
        productID: String,
        location: String? = nil,
        dist: String? = nil,
        authorizedKeys: [String] = [],
        test: Bool = true
    ) {
        self.productID = productID
        self.location = location
        self.dist = dist
        self.authorizedKeys = authorizedKeys
        self.test = test
    }
}

/// A server market (auction) order (`POST /order/server_market`). Market
/// servers are ordered "as-is" — no location or distribution choice.
///
/// `test` defaults to `true` for the same safety reason as `RobotServerOrder`.
public struct RobotMarketOrder: Sendable, Equatable {
    public let productID: String
    /// SSH key fingerprints to authorize on the new server.
    public let authorizedKeys: [String]
    public let test: Bool

    public init(productID: String, authorizedKeys: [String] = [], test: Bool = true) {
        self.productID = productID
        self.authorizedKeys = authorizedKeys
        self.test = test
    }
}

// MARK: - RobotTransaction

/// Status of an order transaction.
public enum RobotTransactionStatus: String, Codable, Sendable, Equatable {
    case inProcess = "in process"
    case ready
    case cancelled
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RobotTransactionStatus(rawValue: raw) ?? .unknown
    }
}

/// Product summary embedded in a `RobotTransaction`.
public struct RobotTransactionProduct: Codable, Sendable, Equatable {
    public let id: String
    public let name: String?
    public let description: [String]?

    enum CodingKeys: String, CodingKey { case id, name, description }

    public init(id: String, name: String? = nil, description: [String]? = nil) {
        self.id = id
        self.name = name
        self.description = description
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(RobotStringOrIntID.self, forKey: .id).value
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        description = try container.decodeIfPresent(RobotStringOrArray.self, forKey: .description)?.values
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
    }
}

/// An authorized SSH key referenced by a transaction. Robot wraps each list
/// element as `{"key": {...}}`, matching the pattern used elsewhere in the
/// Robot Webservice (e.g. `RobotSSHKey` lists).
public struct RobotTransactionAuthorizedKey: Codable, Sendable, Equatable {
    public let name: String?
    public let fingerprint: String?

    enum CodingKeys: String, CodingKey { case name, fingerprint }

    public init(name: String?, fingerprint: String?) {
        self.name = name
        self.fingerprint = fingerprint
    }
}

private struct RobotTransactionAuthorizedKeyEnvelope: Decodable {
    let key: RobotTransactionAuthorizedKey
}

/// The result of placing (or looking up) an order: `POST /order/server`,
/// `POST /order/server_market`, `GET /order/server/transaction[/{id}]`, and
/// the market-order transaction equivalents all return this shape.
public struct RobotTransaction: Sendable, Identifiable, Equatable {
    public let id: String
    /// Raw wire value (Robot emits e.g. `"2023-08-01 17:12:41"`, not strict
    /// ISO 8601) — use `dateValue` for a parsed `Date`.
    public let date: String
    public let status: RobotTransactionStatus
    public let serverNumber: Int?
    public let serverIP: String?
    public let authorizedKeys: [RobotTransactionAuthorizedKey]?
    public let product: RobotTransactionProduct?
    public let comment: String?

    public init(
        id: String,
        date: String,
        status: RobotTransactionStatus,
        serverNumber: Int? = nil,
        serverIP: String? = nil,
        authorizedKeys: [RobotTransactionAuthorizedKey]? = nil,
        product: RobotTransactionProduct? = nil,
        comment: String? = nil
    ) {
        self.id = id
        self.date = date
        self.status = status
        self.serverNumber = serverNumber
        self.serverIP = serverIP
        self.authorizedKeys = authorizedKeys
        self.product = product
        self.comment = comment
    }

    /// `date` parsed as a `Date`. Robot has been observed to emit both a
    /// MySQL-style `"yyyy-MM-dd HH:mm:ss"` value and full ISO 8601 — both are
    /// tried; `nil` if neither matches.
    public var dateValue: Date? {
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = withFractionalSeconds.date(from: date) { return parsed }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let parsed = standard.date(from: date) { return parsed }

        let mysqlStyle = DateFormatter()
        mysqlStyle.calendar = Calendar(identifier: .gregorian)
        mysqlStyle.locale = Locale(identifier: "en_US_POSIX")
        mysqlStyle.timeZone = TimeZone(identifier: "UTC")
        mysqlStyle.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return mysqlStyle.date(from: date)
    }
}

extension RobotTransaction: Decodable {
    enum CodingKeys: String, CodingKey {
        case id, date, status
        case serverNumber = "server_number"
        case serverIP = "server_ip"
        case authorizedKeys = "authorized_key"
        case product, comment
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(RobotStringOrIntID.self, forKey: .id).value
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        status = try container.decodeIfPresent(RobotTransactionStatus.self, forKey: .status) ?? .unknown
        serverNumber = try container.decodeIfPresent(Int.self, forKey: .serverNumber)
        serverIP = try container.decodeIfPresent(String.self, forKey: .serverIP)
        if let wrappedKeys = try? container.decode([RobotTransactionAuthorizedKeyEnvelope].self, forKey: .authorizedKeys) {
            authorizedKeys = wrappedKeys.map(\.key)
        } else if let flatKeys = try? container.decode([RobotTransactionAuthorizedKey].self, forKey: .authorizedKeys) {
            authorizedKeys = flatKeys
        } else {
            authorizedKeys = nil
        }
        product = try container.decodeIfPresent(RobotTransactionProduct.self, forKey: .product)
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
    }
}

/// Wire envelope for transaction endpoints → `{"transaction": {...}}` (each
/// element of a list response is individually wrapped this way too).
struct RobotTransactionEnvelope: Decodable, Sendable {
    let transaction: RobotTransaction
}
