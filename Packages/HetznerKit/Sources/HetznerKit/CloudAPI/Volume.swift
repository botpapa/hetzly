import Foundation

/// A Hetzner Cloud Block Storage volume.
public struct Volume: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let created: Date
    public let name: String
    public let server: Int?
    public let location: Location
    /// Size in GB.
    public let size: Int
    public let linuxDevice: String
    public let protection: VolumeProtection
    public let status: VolumeStatus
    public let format: String?
    public let labels: [String: String]

    enum CodingKeys: String, CodingKey {
        case id, created, name, server, location, size
        case linuxDevice = "linux_device"
        case protection, status, format, labels
    }

    public init(
        id: Int,
        created: Date,
        name: String,
        server: Int?,
        location: Location,
        size: Int,
        linuxDevice: String,
        protection: VolumeProtection,
        status: VolumeStatus,
        format: String?,
        labels: [String: String]
    ) {
        self.id = id
        self.created = created
        self.name = name
        self.server = server
        self.location = location
        self.size = size
        self.linuxDevice = linuxDevice
        self.protection = protection
        self.status = status
        self.format = format
        self.labels = labels
    }
}

/// Volume lifecycle state. Unknown wire values decode to `.unknown` instead
/// of throwing, matching `ServerStatus`.
public enum VolumeStatus: String, Codable, Sendable, Equatable {
    case available, creating
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = VolumeStatus(rawValue: raw) ?? .unknown
    }
}

public struct VolumeProtection: Codable, Sendable, Equatable {
    public let delete: Bool

    enum CodingKeys: String, CodingKey { case delete }

    public init(delete: Bool) {
        self.delete = delete
    }
}

/// Wire envelope for `GET /volumes/{id}` and PUT responses → `{"volume": {...}}`.
struct VolumeEnvelope: Decodable, Sendable {
    let volume: Volume
}

/// Result of `POST /volumes`: the new volume plus the immediate action (when
/// no server was specified) and/or queued next actions (e.g. `attach_volume`
/// when a `server` was specified at creation time).
public struct CreatedVolume: Sendable, Equatable {
    public let volume: Volume
    public let action: Action?
    public let nextActions: [Action]

    public init(volume: Volume, action: Action?, nextActions: [Action]) {
        self.volume = volume
        self.action = action
        self.nextActions = nextActions
    }
}

struct CreateVolumeResponseEnvelope: Decodable, Sendable {
    let volume: Volume
    let action: Action?
    let nextActions: [Action]?

    enum CodingKeys: String, CodingKey {
        case volume, action
        case nextActions = "next_actions"
    }
}
