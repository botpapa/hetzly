import Foundation

extension StorageBoxClient {
    /// All snapshots of `storageBoxID`, fully paginated. `isAutomatic`
    /// filters to snapshot-plan-created (`true`) or manually-created
    /// (`false`) snapshots when supplied — a filter Hetzner added
    /// 21 Oct 2025.
    public func listSnapshots(storageBoxID: Int, isAutomatic: Bool? = nil) async throws -> [StorageBoxSnapshot] {
        var query: [URLQueryItem] = []
        if let isAutomatic {
            query.append(URLQueryItem(name: "is_automatic", value: isAutomatic ? "true" : "false"))
        }

        let stream: AsyncThrowingStream<[StorageBoxSnapshot], Error> = paginated(
            client: client,
            endpoint: Endpoint(path: "/storage_boxes/\(storageBoxID)/snapshots", query: query),
            itemsKey: "snapshots",
            perPage: 50
        )

        var snapshots: [StorageBoxSnapshot] = []
        for try await page in stream {
            snapshots.append(contentsOf: page)
        }
        return snapshots
    }

    public func snapshot(storageBoxID: Int, id: Int) async throws -> StorageBoxSnapshot {
        let envelope: StorageBoxSnapshotEnvelope = try await client.send(
            Endpoint(path: "/storage_boxes/\(storageBoxID)/snapshots/\(id)")
        )
        return envelope.snapshot
    }

    /// Creates a manual snapshot. Returns the new snapshot plus the
    /// queued action.
    public func createSnapshot(
        storageBoxID: Int,
        description: String? = nil,
        labels: [String: String]? = nil
    ) async throws -> (snapshot: StorageBoxSnapshot, action: Action) {
        let body = try JSONEncoder().encode(StorageBoxSnapshotCreateRequest(description: description, labels: labels))
        let envelope: StorageBoxSnapshotCreateResponseEnvelope = try await client.send(
            Endpoint(method: .post, path: "/storage_boxes/\(storageBoxID)/snapshots", body: body)
        )
        return (envelope.snapshot, envelope.action)
    }

    /// Renames the snapshot's `description` and/or relabels it via
    /// `PUT .../snapshots/{id}`. `nil` fields are left unchanged.
    public func updateSnapshot(
        storageBoxID: Int,
        id: Int,
        description: String? = nil,
        labels: [String: String]? = nil
    ) async throws -> StorageBoxSnapshot {
        let body = try JSONEncoder().encode(StorageBoxSnapshotUpdateRequest(description: description, labels: labels))
        let envelope: StorageBoxSnapshotEnvelope = try await client.send(
            Endpoint(method: .put, path: "/storage_boxes/\(storageBoxID)/snapshots/\(id)", body: body)
        )
        return envelope.snapshot
    }

    /// Deletes a snapshot. Like `deleteStorageBox`, this returns
    /// `{"action": {...}}` rather than `204 No Content`.
    public func deleteSnapshot(storageBoxID: Int, id: Int) async throws -> Action {
        let envelope: ActionEnvelope = try await client.send(
            Endpoint(method: .delete, path: "/storage_boxes/\(storageBoxID)/snapshots/\(id)")
        )
        return envelope.action
    }
}

// MARK: - Request bodies

struct StorageBoxSnapshotCreateRequest: Encodable, Sendable {
    let description: String?
    let labels: [String: String]?

    enum CodingKeys: String, CodingKey { case description, labels }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(labels, forKey: .labels)
    }
}

struct StorageBoxSnapshotUpdateRequest: Encodable, Sendable {
    let description: String?
    let labels: [String: String]?

    enum CodingKeys: String, CodingKey { case description, labels }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(labels, forKey: .labels)
    }
}
