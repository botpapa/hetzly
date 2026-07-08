import Foundation

/// A Hetzner Cloud ISO image (mountable via `attachISO`).
public struct ISO: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String?
    public let description: String?
    public let type: ISOType
    /// `nil` for ISOs that aren't architecture-specific.
    public let architecture: Architecture?
    public let deprecation: ISODeprecation?

    enum CodingKeys: String, CodingKey {
        case id, name, description, type, architecture, deprecation
    }

    public init(
        id: Int,
        name: String?,
        description: String?,
        type: ISOType,
        architecture: Architecture?,
        deprecation: ISODeprecation?
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.type = type
        self.architecture = architecture
        self.deprecation = deprecation
    }
}

/// Unknown wire values decode to `.unknown` instead of throwing.
public enum ISOType: String, Codable, Sendable, Equatable {
    case `public`, `private`
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ISOType(rawValue: raw) ?? .unknown
    }
}

public struct ISODeprecation: Codable, Sendable, Equatable {
    public let unavailableAfter: Date
    public let announced: Date

    enum CodingKeys: String, CodingKey {
        case unavailableAfter = "unavailable_after"
        case announced
    }

    public init(unavailableAfter: Date, announced: Date) {
        self.unavailableAfter = unavailableAfter
        self.announced = announced
    }
}

/// Wire envelope for `GET /isos/{id}` → `{"iso": {...}}`.
struct ISOEnvelope: Decodable, Sendable {
    let iso: ISO
}
