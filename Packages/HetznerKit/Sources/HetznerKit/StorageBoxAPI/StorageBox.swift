import Foundation

/// A Hetzner Storage Box, as returned by the current (2025 GA) Storage Box
/// API hosted at `https://api.hetzner.com/v1` — the successor to the
/// deprecated Robot Webservice Storage Box endpoints (`robot-ws.your-server.de`),
/// which Hetzner shut off 30 July 2025. Auth is Bearer-token, same shape as
/// the Cloud API, and — per Hetzner's own changelog note that Storage Boxes
/// "follow Hetzner Cloud API patterns" — list responses are assumed to carry
/// the same `meta.pagination` envelope every other Cloud-style list endpoint
/// in this package relies on (see `StorageBoxClient.listStorageBoxes()`).
public struct StorageBox: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    /// SSH/SMB/WebDAV login name for the box account itself (distinct from
    /// any `StorageBoxSubaccount.username`). `nil` while `status ==
    /// .initializing`.
    public let username: String?
    public let status: StorageBoxStatus
    public let name: String
    public let storageBoxType: StorageBoxType
    public let location: Location
    public let accessSettings: StorageBoxAccessSettings
    /// Hostname used to reach the box (SSH/SFTP/SMB/WebDAV endpoint). `nil`
    /// while `status == .initializing`.
    public let server: String?
    /// Hardware host identifier, e.g. `"FSN1-BX136"`. `nil` while
    /// `status == .initializing`.
    public let system: String?
    public let stats: StorageBoxStats
    public let labels: [String: String]
    public let protection: StorageBoxProtection
    /// `nil` when no automatic snapshot plan is configured.
    public let snapshotPlan: StorageBoxSnapshotPlan?
    public let created: Date

    enum CodingKeys: String, CodingKey {
        case id, username, status, name
        case storageBoxType = "storage_box_type"
        case location
        case accessSettings = "access_settings"
        case server, system, stats, labels, protection
        case snapshotPlan = "snapshot_plan"
        case created
    }

    public init(
        id: Int,
        username: String?,
        status: StorageBoxStatus,
        name: String,
        storageBoxType: StorageBoxType,
        location: Location,
        accessSettings: StorageBoxAccessSettings,
        server: String?,
        system: String?,
        stats: StorageBoxStats,
        labels: [String: String],
        protection: StorageBoxProtection,
        snapshotPlan: StorageBoxSnapshotPlan?,
        created: Date
    ) {
        self.id = id
        self.username = username
        self.status = status
        self.name = name
        self.storageBoxType = storageBoxType
        self.location = location
        self.accessSettings = accessSettings
        self.server = server
        self.system = system
        self.stats = stats
        self.labels = labels
        self.protection = protection
        self.snapshotPlan = snapshotPlan
        self.created = created
    }

    /// Labels decode leniently — see `decodeLenientLabels`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        status = try container.decode(StorageBoxStatus.self, forKey: .status)
        name = try container.decode(String.self, forKey: .name)
        storageBoxType = try container.decode(StorageBoxType.self, forKey: .storageBoxType)
        location = try container.decode(Location.self, forKey: .location)
        accessSettings = try container.decode(StorageBoxAccessSettings.self, forKey: .accessSettings)
        server = try container.decodeIfPresent(String.self, forKey: .server)
        system = try container.decodeIfPresent(String.self, forKey: .system)
        stats = try container.decode(StorageBoxStats.self, forKey: .stats)
        labels = try container.decodeLenientLabels(forKey: .labels)
        protection = try container.decode(StorageBoxProtection.self, forKey: .protection)
        snapshotPlan = try container.decodeIfPresent(StorageBoxSnapshotPlan.self, forKey: .snapshotPlan)
        created = try container.decode(Date.self, forKey: .created)
    }
}

/// Unknown wire values decode to `.unknown` instead of throwing, matching
/// `ServerStatus`/`VolumeStatus` elsewhere in this package.
public enum StorageBoxStatus: String, Codable, Sendable, Equatable {
    case active, initializing, locked
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = StorageBoxStatus(rawValue: raw) ?? .unknown
    }
}

/// Protocol toggles for the box's own (non-subaccount) access. Mutated via
/// `StorageBoxClient.updateAccessSettings(id:...)`.
public struct StorageBoxAccessSettings: Codable, Sendable, Equatable {
    public let reachableExternally: Bool
    public let sambaEnabled: Bool
    public let sshEnabled: Bool
    public let webdavEnabled: Bool
    public let zfsEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case reachableExternally = "reachable_externally"
        case sambaEnabled = "samba_enabled"
        case sshEnabled = "ssh_enabled"
        case webdavEnabled = "webdav_enabled"
        case zfsEnabled = "zfs_enabled"
    }

    public init(
        reachableExternally: Bool,
        sambaEnabled: Bool,
        sshEnabled: Bool,
        webdavEnabled: Bool,
        zfsEnabled: Bool
    ) {
        self.reachableExternally = reachableExternally
        self.sambaEnabled = sambaEnabled
        self.sshEnabled = sshEnabled
        self.webdavEnabled = webdavEnabled
        self.zfsEnabled = zfsEnabled
    }
}

/// Usage in bytes. `sizeData` + `sizeSnapshots` need not equal `size`
/// exactly (filesystem overhead), matching Hetzner's own semantics.
public struct StorageBoxStats: Codable, Sendable, Equatable {
    public let size: Int64
    public let sizeData: Int64
    public let sizeSnapshots: Int64

    enum CodingKeys: String, CodingKey {
        case size
        case sizeData = "size_data"
        case sizeSnapshots = "size_snapshots"
    }

    public init(size: Int64, sizeData: Int64, sizeSnapshots: Int64) {
        self.size = size
        self.sizeData = sizeData
        self.sizeSnapshots = sizeSnapshots
    }
}

public struct StorageBoxProtection: Codable, Sendable, Equatable {
    public let delete: Bool

    enum CodingKeys: String, CodingKey { case delete }

    public init(delete: Bool) {
        self.delete = delete
    }
}

/// Automatic snapshot schedule. `dayOfWeek`/`dayOfMonth` are mutually
/// exclusive and both `nil` means "daily" — matches Hetzner's 21 Oct 2025
/// breaking change requiring `hour`/`minute` on every snapshot plan.
public struct StorageBoxSnapshotPlan: Codable, Sendable, Equatable {
    public let maxSnapshots: Int
    public let minute: Int
    public let hour: Int
    /// ISO weekday, 1 (Monday) ... 7 (Sunday). `nil` = daily.
    public let dayOfWeek: Int?
    /// Day of month, 1...31. `nil` = daily.
    public let dayOfMonth: Int?

    enum CodingKeys: String, CodingKey {
        case maxSnapshots = "max_snapshots"
        case minute, hour
        case dayOfWeek = "day_of_week"
        case dayOfMonth = "day_of_month"
    }

    public init(maxSnapshots: Int, minute: Int, hour: Int, dayOfWeek: Int?, dayOfMonth: Int?) {
        self.maxSnapshots = maxSnapshots
        self.minute = minute
        self.hour = hour
        self.dayOfWeek = dayOfWeek
        self.dayOfMonth = dayOfMonth
    }
}

// MARK: - Wire envelopes

/// `{"storage_box": {...}}` — used by get/update/create responses.
struct StorageBoxEnvelope: Decodable, Sendable {
    let storageBox: StorageBox
    enum CodingKeys: String, CodingKey { case storageBox = "storage_box" }
}

/// `POST /storage_boxes` → `{"storage_box": {...}, "action": {...}}`.
struct StorageBoxCreateResponseEnvelope: Decodable, Sendable {
    let storageBox: StorageBox
    let action: Action
    enum CodingKeys: String, CodingKey { case storageBox = "storage_box", action }
}

/// `GET /storage_boxes/{id}/folders` → `{"folders": ["/", "/backups", ...]}`.
struct StorageBoxFoldersEnvelope: Decodable, Sendable {
    let folders: [String]
}
