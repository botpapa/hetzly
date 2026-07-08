import Foundation

extension StorageBoxClient {
    /// All subaccounts of `storageBoxID`, fully paginated. `username`
    /// filters to an exact username match when supplied.
    public func listSubaccounts(storageBoxID: Int, username: String? = nil) async throws -> [StorageBoxSubaccount] {
        var query: [URLQueryItem] = []
        if let username {
            query.append(URLQueryItem(name: "username", value: username))
        }

        let stream: AsyncThrowingStream<[StorageBoxSubaccount], Error> = paginated(
            client: client,
            endpoint: Endpoint(path: "/storage_boxes/\(storageBoxID)/subaccounts", query: query),
            itemsKey: "subaccounts",
            perPage: 50
        )

        var subaccounts: [StorageBoxSubaccount] = []
        for try await page in stream {
            subaccounts.append(contentsOf: page)
        }
        return subaccounts
    }

    public func subaccount(storageBoxID: Int, id: Int) async throws -> StorageBoxSubaccount {
        let envelope: StorageBoxSubaccountEnvelope = try await client.send(
            Endpoint(path: "/storage_boxes/\(storageBoxID)/subaccounts/\(id)")
        )
        return envelope.subaccount
    }

    /// Creates a subaccount scoped to `homeDirectory`. `password` must
    /// satisfy Hetzner's policy (>=12 chars, at least one special
    /// character). Returns the new subaccount plus the queued action.
    public func createSubaccount(
        storageBoxID: Int,
        homeDirectory: String,
        password: String,
        name: String? = nil,
        description: String? = nil,
        accessSettings: StorageBoxSubaccountAccessSettings? = nil,
        labels: [String: String]? = nil
    ) async throws -> (subaccount: StorageBoxSubaccount, action: Action) {
        let request = StorageBoxSubaccountCreateRequest(
            name: name,
            homeDirectory: homeDirectory,
            password: password,
            description: description,
            accessSettings: accessSettings.map(StorageBoxSubaccountCreateRequestAccessSettings.init),
            labels: labels
        )
        let body = try JSONEncoder().encode(request)
        let envelope: StorageBoxSubaccountCreateResponseEnvelope = try await client.send(
            Endpoint(method: .post, path: "/storage_boxes/\(storageBoxID)/subaccounts", body: body)
        )
        return (envelope.subaccount, envelope.action)
    }

    /// Renames `description`/relabels via `PUT .../subaccounts/{id}`.
    /// `nil` fields are left unchanged.
    public func updateSubaccount(
        storageBoxID: Int,
        id: Int,
        name: String? = nil,
        description: String? = nil,
        labels: [String: String]? = nil
    ) async throws -> StorageBoxSubaccount {
        let request = StorageBoxSubaccountUpdateRequest(name: name, description: description, labels: labels)
        let body = try JSONEncoder().encode(request)
        let envelope: StorageBoxSubaccountEnvelope = try await client.send(
            Endpoint(method: .put, path: "/storage_boxes/\(storageBoxID)/subaccounts/\(id)", body: body)
        )
        return envelope.subaccount
    }

    /// Deletes a subaccount. Returns `{"action": {...}}` rather than
    /// `204 No Content`, matching `deleteSnapshot`/`deleteStorageBox`.
    public func deleteSubaccount(storageBoxID: Int, id: Int) async throws -> Action {
        let envelope: ActionEnvelope = try await client.send(
            Endpoint(method: .delete, path: "/storage_boxes/\(storageBoxID)/subaccounts/\(id)")
        )
        return envelope.action
    }

    /// Resets a subaccount's own login password. `newPassword` is sent ONLY
    /// in the JSON request body — never appended to the URL/query string —
    /// so it never appears in logs that capture request URLs.
    public func resetSubaccountPassword(storageBoxID: Int, id: Int, newPassword: String) async throws -> Action {
        let body = try JSONEncoder().encode(StorageBoxResetPasswordRequest(password: newPassword))
        return try await performSubaccountAction(
            storageBoxID: storageBoxID,
            subaccountID: id,
            action: "reset_subaccount_password",
            body: body
        )
    }

    /// Toggles this subaccount's protocol access and `readonly` flag. Only
    /// non-`nil` parameters are sent, so unspecified settings are left
    /// unchanged.
    public func updateSubaccountAccessSettings(
        storageBoxID: Int,
        id: Int,
        reachableExternally: Bool? = nil,
        readonly: Bool? = nil,
        sambaEnabled: Bool? = nil,
        sshEnabled: Bool? = nil,
        webdavEnabled: Bool? = nil
    ) async throws -> Action {
        let request = StorageBoxSubaccountUpdateAccessSettingsRequest(
            reachableExternally: reachableExternally,
            readonly: readonly,
            sambaEnabled: sambaEnabled,
            sshEnabled: sshEnabled,
            webdavEnabled: webdavEnabled
        )
        let body = try JSONEncoder().encode(request)
        return try await performSubaccountAction(
            storageBoxID: storageBoxID,
            subaccountID: id,
            action: "update_access_settings",
            body: body
        )
    }

    /// Moves the subaccount's scope to a new home directory (added as a
    /// dedicated action endpoint 21 Oct 2025 — previously only settable at
    /// creation time).
    public func changeSubaccountHomeDirectory(storageBoxID: Int, id: Int, homeDirectory: String) async throws -> Action {
        let body = try JSONEncoder().encode(StorageBoxSubaccountChangeHomeDirectoryRequest(homeDirectory: homeDirectory))
        return try await performSubaccountAction(
            storageBoxID: storageBoxID,
            subaccountID: id,
            action: "change_home_directory",
            body: body
        )
    }

    private func performSubaccountAction(
        storageBoxID: Int,
        subaccountID: Int,
        action: String,
        body: Data?
    ) async throws -> Action {
        let envelope: ActionEnvelope = try await client.send(
            Endpoint(
                method: .post,
                path: "/storage_boxes/\(storageBoxID)/subaccounts/\(subaccountID)/actions/\(action)",
                body: body
            )
        )
        return envelope.action
    }
}

// MARK: - Request bodies

struct StorageBoxSubaccountCreateRequest: Encodable, Sendable {
    let name: String?
    let homeDirectory: String
    let password: String
    let description: String?
    let accessSettings: StorageBoxSubaccountCreateRequestAccessSettings?
    let labels: [String: String]?

    enum CodingKeys: String, CodingKey {
        case name
        case homeDirectory = "home_directory"
        case password, description
        case accessSettings = "access_settings"
        case labels
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(homeDirectory, forKey: .homeDirectory)
        try container.encode(password, forKey: .password)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(accessSettings, forKey: .accessSettings)
        try container.encodeIfPresent(labels, forKey: .labels)
    }
}

struct StorageBoxSubaccountCreateRequestAccessSettings: Encodable, Sendable {
    let reachableExternally: Bool
    let readonly: Bool
    let sambaEnabled: Bool
    let sshEnabled: Bool
    let webdavEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case reachableExternally = "reachable_externally"
        case readonly
        case sambaEnabled = "samba_enabled"
        case sshEnabled = "ssh_enabled"
        case webdavEnabled = "webdav_enabled"
    }

    init(from settings: StorageBoxSubaccountAccessSettings) {
        self.reachableExternally = settings.reachableExternally
        self.readonly = settings.readonly
        self.sambaEnabled = settings.sambaEnabled
        self.sshEnabled = settings.sshEnabled
        self.webdavEnabled = settings.webdavEnabled
    }
}

struct StorageBoxSubaccountUpdateRequest: Encodable, Sendable {
    let name: String?
    let description: String?
    let labels: [String: String]?

    enum CodingKeys: String, CodingKey { case name, description, labels }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(labels, forKey: .labels)
    }
}

struct StorageBoxSubaccountUpdateAccessSettingsRequest: Encodable, Sendable {
    let reachableExternally: Bool?
    let readonly: Bool?
    let sambaEnabled: Bool?
    let sshEnabled: Bool?
    let webdavEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case reachableExternally = "reachable_externally"
        case readonly
        case sambaEnabled = "samba_enabled"
        case sshEnabled = "ssh_enabled"
        case webdavEnabled = "webdav_enabled"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(reachableExternally, forKey: .reachableExternally)
        try container.encodeIfPresent(readonly, forKey: .readonly)
        try container.encodeIfPresent(sambaEnabled, forKey: .sambaEnabled)
        try container.encodeIfPresent(sshEnabled, forKey: .sshEnabled)
        try container.encodeIfPresent(webdavEnabled, forKey: .webdavEnabled)
    }
}

struct StorageBoxSubaccountChangeHomeDirectoryRequest: Encodable, Sendable {
    let homeDirectory: String
    enum CodingKeys: String, CodingKey { case homeDirectory = "home_directory" }
}
