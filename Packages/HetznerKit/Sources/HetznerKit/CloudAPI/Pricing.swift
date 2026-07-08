import Foundation

/// Decoded response of `GET /pricing`. Models what the app's cost math
/// needs; everything else on the wire is tolerated but not surfaced.
/// Callers are expected to cache this (~24h) via `ResponseCache`.
public struct Pricing: Sendable, Equatable {
    public let currency: String
    public let vatRate: String
    public let serverTypes: [PricingServerType]
    public let primaryIPs: [PricingPrimaryIP]
    public let volumePerGBMonth: PriceValue?
    public let serverBackupPercentage: String?

    public init(
        currency: String,
        vatRate: String,
        serverTypes: [PricingServerType],
        primaryIPs: [PricingPrimaryIP],
        volumePerGBMonth: PriceValue?,
        serverBackupPercentage: String?
    ) {
        self.currency = currency
        self.vatRate = vatRate
        self.serverTypes = serverTypes
        self.primaryIPs = primaryIPs
        self.volumePerGBMonth = volumePerGBMonth
        self.serverBackupPercentage = serverBackupPercentage
    }
}

public struct PricingServerType: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let prices: [ServerTypePrice]

    enum CodingKeys: String, CodingKey { case id, name, prices }

    public init(id: Int, name: String, prices: [ServerTypePrice]) {
        self.id = id
        self.name = name
        self.prices = prices
    }
}

public struct PricingPrimaryIP: Codable, Sendable, Equatable {
    public let type: String
    public let prices: [ServerTypePrice]

    enum CodingKeys: String, CodingKey { case type, prices }

    public init(type: String, prices: [ServerTypePrice]) {
        self.type = type
        self.prices = prices
    }
}

extension Pricing: Decodable {
    private enum RootKeys: String, CodingKey { case pricing }
    private enum BodyKeys: String, CodingKey {
        case currency
        case vatRate = "vat_rate"
        case serverTypes = "server_types"
        case primaryIPs = "primary_ips"
        case volume
        case serverBackup = "server_backup"
    }
    private enum VolumeKeys: String, CodingKey {
        case pricePerGBMonth = "price_per_gb_month"
    }
    private enum ServerBackupKeys: String, CodingKey {
        case percentage
    }

    public init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: RootKeys.self)
        let body = try root.nestedContainer(keyedBy: BodyKeys.self, forKey: .pricing)

        currency = try body.decode(String.self, forKey: .currency)
        vatRate = try body.decode(String.self, forKey: .vatRate)
        serverTypes = try body.decodeIfPresent([PricingServerType].self, forKey: .serverTypes) ?? []
        primaryIPs = try body.decodeIfPresent([PricingPrimaryIP].self, forKey: .primaryIPs) ?? []

        if let volumeContainer = try? body.nestedContainer(keyedBy: VolumeKeys.self, forKey: .volume) {
            volumePerGBMonth = try? volumeContainer.decode(PriceValue.self, forKey: .pricePerGBMonth)
        } else {
            volumePerGBMonth = nil
        }

        if let backupContainer = try? body.nestedContainer(keyedBy: ServerBackupKeys.self, forKey: .serverBackup) {
            serverBackupPercentage = try? backupContainer.decode(String.self, forKey: .percentage)
        } else {
            serverBackupPercentage = nil
        }
    }
}
