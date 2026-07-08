import Foundation

/// A point-in-time snapshot of a `StorageBox`
/// (`/storage_boxes/{id}/snapshots`).
public struct StorageBoxSnapshot: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let description: String
    public let stats: StorageBoxSnapshotStats
    /// `true` when created by a `StorageBoxSnapshotPlan` rather than a
    /// manual `createSnapshot` call. Filterable via
    /// `StorageBoxClient.listSnapshots(storageBoxID:isAutomatic:)`.
    public let isAutomatic: Bool
    public let labels: [String: String]
    public let created: Date
    /// The owning storage box's ID (wire value is a bare integer, not a
    /// nested object).
    public let storageBoxID: Int

    enum CodingKeys: String, CodingKey {
        case id, name, description, stats
        case isAutomatic = "is_automatic"
        case labels, created
        case storageBoxID = "storage_box"
    }

    public init(
        id: Int,
        name: String,
        description: String,
        stats: StorageBoxSnapshotStats,
        isAutomatic: Bool,
        labels: [String: String],
        created: Date,
        storageBoxID: Int
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.stats = stats
        self.isAutomatic = isAutomatic
        self.labels = labels
        self.created = created
        self.storageBoxID = storageBoxID
    }

    /// Labels decode leniently — see `decodeLenientLabels`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        stats = try container.decode(StorageBoxSnapshotStats.self, forKey: .stats)
        isAutomatic = try container.decode(Bool.self, forKey: .isAutomatic)
        labels = try container.decodeLenientLabels(forKey: .labels)
        created = try container.decode(Date.self, forKey: .created)
        storageBoxID = try container.decode(Int.self, forKey: .storageBoxID)
    }
}

public struct StorageBoxSnapshotStats: Codable, Sendable, Equatable {
    /// Snapshot size in bytes.
    public let size: Int64
    /// Size the restored filesystem would occupy, in bytes.
    public let sizeFilesystem: Int64

    enum CodingKeys: String, CodingKey {
        case size
        case sizeFilesystem = "size_filesystem"
    }

    public init(size: Int64, sizeFilesystem: Int64) {
        self.size = size
        self.sizeFilesystem = sizeFilesystem
    }
}

// MARK: - Wire envelopes

/// `{"snapshot": {...}}` — get/update responses.
struct StorageBoxSnapshotEnvelope: Decodable, Sendable {
    let snapshot: StorageBoxSnapshot
}

/// `{"snapshots": [...]}` — used with `paginated(itemsKey: "snapshots")`.
/// `POST .../snapshots` → `{"snapshot": {...}, "action": {...}}`.
struct StorageBoxSnapshotCreateResponseEnvelope: Decodable, Sendable {
    let snapshot: StorageBoxSnapshot
    let action: Action
}
