import Foundation

/// High-level client for Hetzner's Storage Box API
/// (`https://api.hetzner.com/v1`) — GA since 25 June 2025, replacing the
/// deprecated Robot Webservice Storage Box endpoints (removed 30 July
/// 2025). Bearer-token auth, same request/response conventions as the Cloud
/// API (`{"storage_box": {...}}` / `{"storage_boxes": [...]}` envelopes,
/// `{"action": {...}}` for async operations, `{"error": {"code",
/// "message"}}` for failures) — this client reuses `Action`/`ActionEnvelope`
/// from `CloudAPI` (same module) and the shared `HetznerErrorEnvelope`
/// mapping already built into `HetznerHTTPClient`.
///
/// Rate limit budget: Hetzner's documentation for the exact
/// `storage_boxes` quota was not directly confirmed (the Redoc reference at
/// docs.hetzner.cloud is client-rendered and didn't return static content
/// to this worker's fetch tooling) — this uses the same conservative
/// 3600/hour budget as `CloudClient`, since the API is documented to follow
/// Cloud API conventions and `RateLimiter.record(response:)` will tighten
/// the effective budget from live `RateLimit-*` response headers regardless.
public actor StorageBoxClient {
    // `internal` (not `private`) so `extension StorageBoxClient` files
    // (Snapshots, Subaccounts) can share this actor's single rate-limited
    // `HetznerHTTPClient` — mirrors the documented `CloudClient`/
    // `RobotClient` precedent (see CONTRACTS.md "M2 Wave A contracts").
    let client: HetznerHTTPClient

    private static let baseURL = URL(string: "https://api.hetzner.com/v1")!

    public init(token: String, transport: HTTPTransport = URLSessionTransport()) {
        let configuration = APIConfiguration(baseURL: Self.baseURL, auth: .bearer(token: token))
        self.client = HetznerHTTPClient(
            configuration: configuration,
            transport: transport,
            rateLimiter: RateLimiter(budget: 3600, window: 3600)
        )
    }

    /// Cheap authenticated GET (`/storage_box_types`, a public catalog that
    /// doesn't require owning any boxes) to confirm the token is accepted.
    /// Throws `HetznerAPIError.unauthorized` on a bad token.
    public func validateToken() async throws {
        _ = try await listStorageBoxTypes()
    }

    // MARK: - Storage boxes

    /// All storage boxes owned by this token, fully paginated.
    public func listStorageBoxes() async throws -> [StorageBox] {
        let stream: AsyncThrowingStream<[StorageBox], Error> = paginated(
            client: client,
            endpoint: Endpoint(path: "/storage_boxes"),
            itemsKey: "storage_boxes",
            perPage: 50
        )

        var boxes: [StorageBox] = []
        for try await page in stream {
            boxes.append(contentsOf: page)
        }
        return boxes
    }

    public func storageBox(id: Int) async throws -> StorageBox {
        let envelope: StorageBoxEnvelope = try await client.send(Endpoint(path: "/storage_boxes/\(id)"))
        return envelope.storageBox
    }

    /// Orders a new storage box. `storageBoxType`/`location` accept either
    /// a numeric ID or a name, matching the "ID or name" string convention
    /// `CloudClient.rebuild(imageIDOrName:)` already uses for the same kind
    /// of Hetzner wire field. `password` must satisfy Hetzner's policy
    /// (>=12 chars, at least one special character, effective 17 Sep 2025).
    public func createStorageBox(
        name: String,
        storageBoxType: String,
        location: String,
        password: String,
        sshKeys: [String]? = nil,
        accessSettings: StorageBoxAccessSettings? = nil,
        labels: [String: String]? = nil
    ) async throws -> (storageBox: StorageBox, action: Action) {
        let request = StorageBoxCreateRequest(
            name: name,
            storageBoxType: storageBoxType,
            location: location,
            labels: labels,
            password: password,
            sshKeys: sshKeys,
            accessSettings: accessSettings.map(StorageBoxCreateRequestAccessSettings.init)
        )
        let body = try JSONEncoder().encode(request)
        let envelope: StorageBoxCreateResponseEnvelope = try await client.send(
            Endpoint(method: .post, path: "/storage_boxes", body: body)
        )
        return (envelope.storageBox, envelope.action)
    }

    /// Renames and/or relabels a box via `PUT /storage_boxes/{id}`.
    /// `nil` fields are omitted from the request body (left unchanged).
    public func updateStorageBox(
        id: Int,
        name: String? = nil,
        labels: [String: String]? = nil
    ) async throws -> StorageBox {
        let request = StorageBoxUpdateRequest(name: name, labels: labels)
        let body = try JSONEncoder().encode(request)
        let envelope: StorageBoxEnvelope = try await client.send(
            Endpoint(method: .put, path: "/storage_boxes/\(id)", body: body)
        )
        return envelope.storageBox
    }

    /// Deletes a storage box. Unlike Cloud volumes (`204 No Content`), this
    /// returns `{"action": {...}}` — the same async-action pattern as
    /// server deletion.
    public func deleteStorageBox(id: Int) async throws -> Action {
        let envelope: ActionEnvelope = try await client.send(Endpoint(method: .delete, path: "/storage_boxes/\(id)"))
        return envelope.action
    }

    public func changeProtection(id: Int, delete: Bool) async throws -> Action {
        let body = try JSONEncoder().encode(StorageBoxChangeProtectionRequest(delete: delete))
        return try await performAction(id: id, action: "change_protection", body: body)
    }

    /// `storageBoxType` accepts either a numeric ID or a name.
    public func changeType(id: Int, storageBoxType: String) async throws -> Action {
        let body = try JSONEncoder().encode(StorageBoxChangeTypeRequest(storageBoxType: storageBoxType))
        return try await performAction(id: id, action: "change_type", body: body)
    }

    /// Resets the box's own login password. `newPassword` is sent ONLY in
    /// the JSON request body (never appended to the URL/query string), so
    /// it never appears in logs that capture request URLs.
    public func resetPassword(id: Int, newPassword: String) async throws -> Action {
        let body = try JSONEncoder().encode(StorageBoxResetPasswordRequest(password: newPassword))
        return try await performAction(id: id, action: "reset_password", body: body)
    }

    /// Toggles one or more protocols (Samba/CIFS, SSH/SFTP, WebDAV, ZFS) and
    /// external reachability. Only non-`nil` parameters are sent, so
    /// unspecified settings are left unchanged.
    public func updateAccessSettings(
        id: Int,
        reachableExternally: Bool? = nil,
        sambaEnabled: Bool? = nil,
        sshEnabled: Bool? = nil,
        webdavEnabled: Bool? = nil,
        zfsEnabled: Bool? = nil
    ) async throws -> Action {
        let request = StorageBoxUpdateAccessSettingsRequest(
            reachableExternally: reachableExternally,
            sambaEnabled: sambaEnabled,
            sshEnabled: sshEnabled,
            webdavEnabled: webdavEnabled,
            zfsEnabled: zfsEnabled
        )
        let body = try JSONEncoder().encode(request)
        return try await performAction(id: id, action: "update_access_settings", body: body)
    }

    /// Rolls the box back to `snapshot` (accepts either a numeric snapshot
    /// ID or a snapshot name, per Hetzner's 21 Oct 2025 change).
    public func rollbackSnapshot(id: Int, snapshot: String) async throws -> Action {
        let body = try JSONEncoder().encode(StorageBoxRollbackSnapshotRequest(snapshot: snapshot))
        return try await performAction(id: id, action: "rollback_snapshot", body: body)
    }

    /// `dayOfWeek` (1=Monday...7=Sunday) and `dayOfMonth` (1...31) are
    /// mutually exclusive; leave both `nil` for a daily plan.
    public func enableSnapshotPlan(
        id: Int,
        maxSnapshots: Int,
        minute: Int,
        hour: Int,
        dayOfWeek: Int? = nil,
        dayOfMonth: Int? = nil
    ) async throws -> Action {
        let request = StorageBoxEnableSnapshotPlanRequest(
            maxSnapshots: maxSnapshots,
            minute: minute,
            hour: hour,
            dayOfWeek: dayOfWeek,
            dayOfMonth: dayOfMonth
        )
        let body = try JSONEncoder().encode(request)
        return try await performAction(id: id, action: "enable_snapshot_plan", body: body)
    }

    public func disableSnapshotPlan(id: Int) async throws -> Action {
        try await performAction(id: id, action: "disable_snapshot_plan", body: nil)
    }

    /// Lists folder paths at the top level of the box, or under `path` when
    /// supplied (e.g. `"/backups"`).
    public func folders(id: Int, path: String? = nil) async throws -> [String] {
        var query: [URLQueryItem] = []
        if let path {
            query.append(URLQueryItem(name: "path", value: path))
        }
        let envelope: StorageBoxFoldersEnvelope = try await client.send(
            Endpoint(path: "/storage_boxes/\(id)/folders", query: query)
        )
        return envelope.folders
    }

    // MARK: - Storage box types (catalog)

    /// All available storage box tiers/plans. Small, rarely-changing
    /// catalog — callers may want to cache this via `ResponseCache`,
    /// mirroring `CloudClient.pricing()`.
    public func listStorageBoxTypes() async throws -> [StorageBoxType] {
        let stream: AsyncThrowingStream<[StorageBoxType], Error> = paginated(
            client: client,
            endpoint: Endpoint(path: "/storage_box_types"),
            itemsKey: "storage_box_types",
            perPage: 50
        )

        var types: [StorageBoxType] = []
        for try await page in stream {
            types.append(contentsOf: page)
        }
        return types
    }

    public func storageBoxType(id: Int) async throws -> StorageBoxType {
        let envelope: StorageBoxTypeEnvelope = try await client.send(Endpoint(path: "/storage_box_types/\(id)"))
        return envelope.storageBoxType
    }

    // MARK: - Shared action helper (used by this file and the Snapshots/Subaccounts extensions)

    func performAction(id: Int, action: String, body: Data?) async throws -> Action {
        let envelope: ActionEnvelope = try await client.send(
            Endpoint(method: .post, path: "/storage_boxes/\(id)/actions/\(action)", body: body)
        )
        return envelope.action
    }
}

// MARK: - Request bodies

struct StorageBoxCreateRequest: Encodable, Sendable {
    let name: String
    let storageBoxType: String
    let location: String
    let labels: [String: String]?
    let password: String
    let sshKeys: [String]?
    let accessSettings: StorageBoxCreateRequestAccessSettings?

    enum CodingKeys: String, CodingKey {
        case name
        case storageBoxType = "storage_box_type"
        case location, labels, password
        case sshKeys = "ssh_keys"
        case accessSettings = "access_settings"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(storageBoxType, forKey: .storageBoxType)
        try container.encode(location, forKey: .location)
        try container.encodeIfPresent(labels, forKey: .labels)
        try container.encode(password, forKey: .password)
        try container.encodeIfPresent(sshKeys, forKey: .sshKeys)
        try container.encodeIfPresent(accessSettings, forKey: .accessSettings)
    }
}

struct StorageBoxCreateRequestAccessSettings: Encodable, Sendable {
    let reachableExternally: Bool
    let sambaEnabled: Bool
    let sshEnabled: Bool
    let webdavEnabled: Bool
    let zfsEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case reachableExternally = "reachable_externally"
        case sambaEnabled = "samba_enabled"
        case sshEnabled = "ssh_enabled"
        case webdavEnabled = "webdav_enabled"
        case zfsEnabled = "zfs_enabled"
    }

    init(from settings: StorageBoxAccessSettings) {
        self.reachableExternally = settings.reachableExternally
        self.sambaEnabled = settings.sambaEnabled
        self.sshEnabled = settings.sshEnabled
        self.webdavEnabled = settings.webdavEnabled
        self.zfsEnabled = settings.zfsEnabled
    }
}

struct StorageBoxUpdateRequest: Encodable, Sendable {
    let name: String?
    let labels: [String: String]?

    enum CodingKeys: String, CodingKey { case name, labels }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(labels, forKey: .labels)
    }
}

struct StorageBoxChangeProtectionRequest: Encodable, Sendable {
    let delete: Bool
    enum CodingKeys: String, CodingKey { case delete }
}

struct StorageBoxChangeTypeRequest: Encodable, Sendable {
    let storageBoxType: String
    enum CodingKeys: String, CodingKey { case storageBoxType = "storage_box_type" }
}

struct StorageBoxResetPasswordRequest: Encodable, Sendable {
    let password: String
    enum CodingKeys: String, CodingKey { case password }
}

struct StorageBoxUpdateAccessSettingsRequest: Encodable, Sendable {
    let reachableExternally: Bool?
    let sambaEnabled: Bool?
    let sshEnabled: Bool?
    let webdavEnabled: Bool?
    let zfsEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case reachableExternally = "reachable_externally"
        case sambaEnabled = "samba_enabled"
        case sshEnabled = "ssh_enabled"
        case webdavEnabled = "webdav_enabled"
        case zfsEnabled = "zfs_enabled"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(reachableExternally, forKey: .reachableExternally)
        try container.encodeIfPresent(sambaEnabled, forKey: .sambaEnabled)
        try container.encodeIfPresent(sshEnabled, forKey: .sshEnabled)
        try container.encodeIfPresent(webdavEnabled, forKey: .webdavEnabled)
        try container.encodeIfPresent(zfsEnabled, forKey: .zfsEnabled)
    }
}

struct StorageBoxRollbackSnapshotRequest: Encodable, Sendable {
    let snapshot: String
    enum CodingKeys: String, CodingKey { case snapshot }
}

struct StorageBoxEnableSnapshotPlanRequest: Encodable, Sendable {
    let maxSnapshots: Int
    let minute: Int
    let hour: Int
    let dayOfWeek: Int?
    let dayOfMonth: Int?

    enum CodingKeys: String, CodingKey {
        case maxSnapshots = "max_snapshots"
        case minute, hour
        case dayOfWeek = "day_of_week"
        case dayOfMonth = "day_of_month"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(maxSnapshots, forKey: .maxSnapshots)
        try container.encode(minute, forKey: .minute)
        try container.encode(hour, forKey: .hour)
        try container.encodeIfPresent(dayOfWeek, forKey: .dayOfWeek)
        try container.encodeIfPresent(dayOfMonth, forKey: .dayOfMonth)
    }
}
