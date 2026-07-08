import Foundation

/// A Storage Box tier/plan (`GET /storage_box_types`), embedded on every
/// `StorageBox.storageBoxType` and independently listable as a catalog
/// (mirrors `ServerType` in CloudAPI).
public struct StorageBoxType: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let description: String
    /// Total capacity in bytes.
    public let size: Int64
    /// Max manual snapshots retained; `nil` if unlimited/not applicable.
    public let snapshotLimit: Int?
    /// Max automatic (snapshot-plan) snapshots retained; `nil` if
    /// unlimited/not applicable.
    public let automaticSnapshotLimit: Int?
    public let subaccountsLimit: Int
    public let prices: [StorageBoxTypePrice]
    /// Announcement/unavailability window for a deprecated type; `nil` when
    /// not deprecated. Reuses `ServerTypeDeprecation`'s identical
    /// `{announced, unavailable_after}` shape (same module).
    public let deprecation: ServerTypeDeprecation?

    enum CodingKeys: String, CodingKey {
        case id, name, description, size
        case snapshotLimit = "snapshot_limit"
        case automaticSnapshotLimit = "automatic_snapshot_limit"
        case subaccountsLimit = "subaccounts_limit"
        case prices, deprecation
    }

    public init(
        id: Int,
        name: String,
        description: String,
        size: Int64,
        snapshotLimit: Int?,
        automaticSnapshotLimit: Int?,
        subaccountsLimit: Int,
        prices: [StorageBoxTypePrice],
        deprecation: ServerTypeDeprecation?
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.size = size
        self.snapshotLimit = snapshotLimit
        self.automaticSnapshotLimit = automaticSnapshotLimit
        self.subaccountsLimit = subaccountsLimit
        self.prices = prices
        self.deprecation = deprecation
    }
}

/// A storage box type's price at one location. Distinct from
/// `ServerTypePrice` because storage box types additionally carry a
/// one-time `setupFee`.
public struct StorageBoxTypePrice: Codable, Sendable, Equatable {
    public let location: String
    public let hourly: PriceValue
    public let monthly: PriceValue
    public let setupFee: PriceValue

    enum CodingKeys: String, CodingKey {
        case location
        case hourly = "price_hourly"
        case monthly = "price_monthly"
        case setupFee = "setup_fee"
    }

    public init(location: String, hourly: PriceValue, monthly: PriceValue, setupFee: PriceValue) {
        self.location = location
        self.hourly = hourly
        self.monthly = monthly
        self.setupFee = setupFee
    }
}

/// `{"storage_box_type": {...}}`.
struct StorageBoxTypeEnvelope: Decodable, Sendable {
    let storageBoxType: StorageBoxType
    enum CodingKeys: String, CodingKey { case storageBoxType = "storage_box_type" }
}
