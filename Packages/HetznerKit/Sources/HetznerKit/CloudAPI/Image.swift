import Foundation

/// A Hetzner Cloud image (system, custom snapshot, backup, or one-click app).
public struct Image: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let type: ImageType
    public let status: ImageStatus
    public let name: String?
    public let description: String
    /// Size of the image file itself, in GB. `nil` for system images.
    public let imageSize: Double?
    /// Size of the disk the image was created from, in GB.
    public let diskSize: Double
    public let created: Date
    public let createdFrom: ImageCreator?
    /// ID of the server this image is bound to, if it can only be used to
    /// rebuild that one server (some backups/snapshots).
    public let boundTo: Int?
    public let osFlavor: String
    public let osVersion: String?
    public let architecture: Architecture
    public let protection: ImageProtection
    /// `nil` when the image isn't deprecated.
    public let deprecated: Date?
    public let labels: [String: String]

    enum CodingKeys: String, CodingKey {
        case id, type, status, name, description
        case imageSize = "image_size"
        case diskSize = "disk_size"
        case created
        case createdFrom = "created_from"
        case boundTo = "bound_to"
        case osFlavor = "os_flavor"
        case osVersion = "os_version"
        case architecture, protection, deprecated, labels
    }

    public init(
        id: Int,
        type: ImageType,
        status: ImageStatus,
        name: String?,
        description: String,
        imageSize: Double?,
        diskSize: Double,
        created: Date,
        createdFrom: ImageCreator?,
        boundTo: Int?,
        osFlavor: String,
        osVersion: String?,
        architecture: Architecture,
        protection: ImageProtection,
        deprecated: Date?,
        labels: [String: String]
    ) {
        self.id = id
        self.type = type
        self.status = status
        self.name = name
        self.description = description
        self.imageSize = imageSize
        self.diskSize = diskSize
        self.created = created
        self.createdFrom = createdFrom
        self.boundTo = boundTo
        self.osFlavor = osFlavor
        self.osVersion = osVersion
        self.architecture = architecture
        self.protection = protection
        self.deprecated = deprecated
        self.labels = labels
    }
}

/// Unknown wire values decode to `.unknown` instead of throwing.
public enum ImageType: String, Codable, Sendable, Equatable {
    case system, snapshot, backup, app
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ImageType(rawValue: raw) ?? .unknown
    }
}

/// Unknown wire values decode to `.unknown` instead of throwing.
public enum ImageStatus: String, Codable, Sendable, Equatable {
    case available, creating, unavailable
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ImageStatus(rawValue: raw) ?? .unknown
    }
}

public struct ImageCreator: Codable, Sendable, Equatable {
    public let id: Int
    public let name: String

    enum CodingKeys: String, CodingKey { case id, name }

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

public struct ImageProtection: Codable, Sendable, Equatable {
    public let delete: Bool

    enum CodingKeys: String, CodingKey { case delete }

    public init(delete: Bool) {
        self.delete = delete
    }
}

/// Wire envelope for `GET/PUT /images/{id}` → `{"image": {...}}`.
struct ImageEnvelope: Decodable, Sendable {
    let image: Image
}
