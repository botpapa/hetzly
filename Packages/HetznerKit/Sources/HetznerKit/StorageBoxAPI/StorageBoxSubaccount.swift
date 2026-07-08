import Foundation

/// A restricted sub-login scoped to one directory of a `StorageBox`
/// (`/storage_boxes/{id}/subaccounts`). Distinct from the box's own
/// `username`/`accessSettings` — a subaccount has its own credentials, home
/// directory, and protocol toggles (plus an optional `readonly` flag the
/// top-level box doesn't have).
public struct StorageBoxSubaccount: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    /// Added 15 Jan 2026 for disambiguation beyond `username` — optional
    /// on older responses.
    public let name: String?
    public let username: String
    public let homeDirectory: String
    /// Hostname used to reach this subaccount.
    public let server: String
    public let accessSettings: StorageBoxSubaccountAccessSettings
    public let description: String
    public let labels: [String: String]
    public let created: Date
    /// The owning storage box's ID (wire value is a bare integer, not a
    /// nested object) — matches `StorageBoxSnapshot.storageBoxID`.
    public let storageBoxID: Int

    enum CodingKeys: String, CodingKey {
        case id, name, username
        case homeDirectory = "home_directory"
        case server
        case accessSettings = "access_settings"
        case description, labels, created
        case storageBoxID = "storage_box"
    }

    public init(
        id: Int,
        name: String?,
        username: String,
        homeDirectory: String,
        server: String,
        accessSettings: StorageBoxSubaccountAccessSettings,
        description: String,
        labels: [String: String],
        created: Date,
        storageBoxID: Int
    ) {
        self.id = id
        self.name = name
        self.username = username
        self.homeDirectory = homeDirectory
        self.server = server
        self.accessSettings = accessSettings
        self.description = description
        self.labels = labels
        self.created = created
        self.storageBoxID = storageBoxID
    }

    /// Labels decode leniently — see `decodeLenientLabels`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        username = try container.decode(String.self, forKey: .username)
        homeDirectory = try container.decode(String.self, forKey: .homeDirectory)
        server = try container.decode(String.self, forKey: .server)
        accessSettings = try container.decode(StorageBoxSubaccountAccessSettings.self, forKey: .accessSettings)
        description = try container.decode(String.self, forKey: .description)
        labels = try container.decodeLenientLabels(forKey: .labels)
        created = try container.decode(Date.self, forKey: .created)
        storageBoxID = try container.decode(Int.self, forKey: .storageBoxID)
    }
}

/// Subaccounts add a `readonly` toggle the top-level box's
/// `StorageBoxAccessSettings` doesn't have; otherwise the same protocol
/// flags (subaccounts have no `zfsEnabled` — ZFS access isn't scoped per
/// subaccount).
public struct StorageBoxSubaccountAccessSettings: Codable, Sendable, Equatable {
    public let reachableExternally: Bool
    public let readonly: Bool
    public let sambaEnabled: Bool
    public let sshEnabled: Bool
    public let webdavEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case reachableExternally = "reachable_externally"
        case readonly
        case sambaEnabled = "samba_enabled"
        case sshEnabled = "ssh_enabled"
        case webdavEnabled = "webdav_enabled"
    }

    public init(
        reachableExternally: Bool,
        readonly: Bool,
        sambaEnabled: Bool,
        sshEnabled: Bool,
        webdavEnabled: Bool
    ) {
        self.reachableExternally = reachableExternally
        self.readonly = readonly
        self.sambaEnabled = sambaEnabled
        self.sshEnabled = sshEnabled
        self.webdavEnabled = webdavEnabled
    }
}

// MARK: - Wire envelopes

/// `{"subaccount": {...}}` — get/update responses.
struct StorageBoxSubaccountEnvelope: Decodable, Sendable {
    let subaccount: StorageBoxSubaccount
}

/// `POST .../subaccounts` → `{"subaccount": {...}, "action": {...}}`.
struct StorageBoxSubaccountCreateResponseEnvelope: Decodable, Sendable {
    let subaccount: StorageBoxSubaccount
    let action: Action
}
