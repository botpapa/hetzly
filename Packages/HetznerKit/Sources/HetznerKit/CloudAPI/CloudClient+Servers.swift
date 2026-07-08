import Foundation

/// Server lifecycle operations beyond the core power actions in
/// `CloudClient.swift`: creation, rebuild/resize, rescue mode, backups,
/// imaging, protection, credentials, console access, renaming/labels, and
/// ISO attach/detach.
extension CloudClient {
    /// `POST /servers`. `result.rootPassword` (when present, i.e. no SSH keys
    /// were supplied) is a secret — the caller is responsible for not logging
    /// or persisting it in plaintext.
    public func createServer(_ request: CreateServerRequest) async throws -> CreateServerResult {
        let body = try JSONEncoder().encode(request)
        let endpoint = Endpoint(method: .post, path: "/servers", body: body)
        return try await client.send(endpoint)
    }

    /// Rebuilds the server from `imageIDOrName` (a numeric image ID or an
    /// image name such as `"ubuntu-24.04"`, both accepted by the wire API as
    /// a string).
    public func rebuild(serverID: Int, imageIDOrName: String) async throws -> Action {
        let body = try JSONEncoder().encode(RebuildRequest(image: imageIDOrName))
        return try await performServerAction(
            Endpoint(method: .post, path: "/servers/\(serverID)/actions/rebuild", body: body)
        )
    }

    /// Changes the server type (resize). `upgradeDisk` must be `true` when
    /// downgrading isn't the goal and the new type has a larger disk — once
    /// upgraded, the disk cannot be shrunk back.
    public func changeType(serverID: Int, serverTypeID: Int, upgradeDisk: Bool) async throws -> Action {
        let body = try JSONEncoder().encode(
            ChangeTypeRequest(serverType: serverTypeID, upgradeDisk: upgradeDisk)
        )
        return try await performServerAction(
            Endpoint(method: .post, path: "/servers/\(serverID)/actions/change_type", body: body)
        )
    }

    /// Enables rescue mode. Returns the one-time rescue root password.
    public func enableRescue(serverID: Int, sshKeyIDs: [Int] = []) async throws -> RescueResult {
        let body = try JSONEncoder().encode(EnableRescueRequest(type: "linux64", sshKeys: sshKeyIDs))
        let endpoint = Endpoint(method: .post, path: "/servers/\(serverID)/actions/enable_rescue", body: body)
        return try await client.send(endpoint)
    }

    public func disableRescue(serverID: Int) async throws -> Action {
        try await performServerAction(
            Endpoint(method: .post, path: "/servers/\(serverID)/actions/disable_rescue")
        )
    }

    public func enableBackups(serverID: Int) async throws -> Action {
        try await performServerAction(
            Endpoint(method: .post, path: "/servers/\(serverID)/actions/enable_backup")
        )
    }

    public func disableBackups(serverID: Int) async throws -> Action {
        try await performServerAction(
            Endpoint(method: .post, path: "/servers/\(serverID)/actions/disable_backup")
        )
    }

    /// Creates an image (snapshot or backup) from the server's current disk.
    public func createImage(
        serverID: Int,
        description: String? = nil,
        type: CreateImageType = .snapshot
    ) async throws -> CreatedImage {
        let body = try JSONEncoder().encode(CreateImageRequest(description: description, type: type))
        let endpoint = Endpoint(method: .post, path: "/servers/\(serverID)/actions/create_image", body: body)
        return try await client.send(endpoint)
    }

    /// At least one of `delete`/`rebuild` should be non-`nil`; whichever is
    /// `nil` is omitted from the request and left unchanged server-side.
    public func changeProtection(serverID: Int, delete: Bool? = nil, rebuild: Bool? = nil) async throws -> Action {
        let body = try JSONEncoder().encode(ChangeServerProtectionRequest(delete: delete, rebuild: rebuild))
        return try await performServerAction(
            Endpoint(method: .post, path: "/servers/\(serverID)/actions/change_protection", body: body)
        )
    }

    /// Resets the server's root password. Returns the new one-time password —
    /// a secret the caller must not log or persist in plaintext.
    public func resetPassword(serverID: Int) async throws -> RescueResult {
        let endpoint = Endpoint(method: .post, path: "/servers/\(serverID)/actions/reset_password")
        return try await client.send(endpoint)
    }

    /// Requests a web console (VNC-over-websocket) session. `password` is a
    /// secret — the caller must not log or persist it in plaintext.
    public func requestConsole(serverID: Int) async throws -> ConsoleResult {
        let endpoint = Endpoint(method: .post, path: "/servers/\(serverID)/actions/request_console")
        return try await client.send(endpoint)
    }

    public func rename(serverID: Int, name: String) async throws -> Server {
        let body = try JSONEncoder().encode(RenameServerRequest(name: name))
        let endpoint = Endpoint(method: .put, path: "/servers/\(serverID)", body: body)
        let envelope: ServerEnvelope = try await client.send(endpoint)
        return envelope.server
    }

    public func updateLabels(serverID: Int, labels: [String: String]) async throws -> Server {
        let body = try JSONEncoder().encode(UpdateServerLabelsRequest(labels: labels))
        let endpoint = Endpoint(method: .put, path: "/servers/\(serverID)", body: body)
        let envelope: ServerEnvelope = try await client.send(endpoint)
        return envelope.server
    }

    /// Attaches an ISO by numeric ID or name (both accepted as a string by
    /// the wire API), e.g. `"debian-12-netinst-amd64"`.
    public func attachISO(serverID: Int, iso: String) async throws -> Action {
        let body = try JSONEncoder().encode(AttachISORequest(iso: iso))
        return try await performServerAction(
            Endpoint(method: .post, path: "/servers/\(serverID)/actions/attach_iso", body: body)
        )
    }

    public func detachISO(serverID: Int) async throws -> Action {
        try await performServerAction(
            Endpoint(method: .post, path: "/servers/\(serverID)/actions/detach_iso")
        )
    }

    /// Shared helper for this file's `{"action": {...}}`-shaped endpoints.
    /// (`CloudClient.swift` has its own private helper of the same shape —
    /// `private` is file-scoped in Swift, so each extension file defines the
    /// small amount of duplicate glue it needs rather than sharing it.)
    private func performServerAction(_ endpoint: Endpoint) async throws -> Action {
        let envelope: ActionEnvelope = try await client.send(endpoint)
        return envelope.action
    }
}

// MARK: - Request bodies

private struct RebuildRequest: Encodable {
    let image: String
}

private struct ChangeTypeRequest: Encodable {
    let serverType: Int
    let upgradeDisk: Bool

    enum CodingKeys: String, CodingKey {
        case serverType = "server_type"
        case upgradeDisk = "upgrade_disk"
    }
}

private struct EnableRescueRequest: Encodable {
    let type: String
    let sshKeys: [Int]

    enum CodingKeys: String, CodingKey {
        case type
        case sshKeys = "ssh_keys"
    }
}

/// Distinct from the full `ImageType` (which also decodes `system`/`app`):
/// `create_image` only ever accepts `snapshot` or `backup` on the wire.
public enum CreateImageType: String, Encodable, Sendable, Equatable {
    case snapshot, backup
}

private struct CreateImageRequest: Encodable {
    let description: String?
    let type: CreateImageType
}

private struct ChangeServerProtectionRequest: Encodable {
    let delete: Bool?
    let rebuild: Bool?
}

private struct RenameServerRequest: Encodable {
    let name: String
}

private struct UpdateServerLabelsRequest: Encodable {
    let labels: [String: String]
}

private struct AttachISORequest: Encodable {
    let iso: String
}

// MARK: - Multi-value results

/// `{"root_password", "action"}` shape shared by `enableRescue` and
/// `resetPassword`. `rootPassword` is a secret.
public struct RescueResult: Decodable, Sendable, Equatable {
    public let rootPassword: String
    public let action: Action

    enum CodingKeys: String, CodingKey {
        case rootPassword = "root_password"
        case action
    }

    public init(rootPassword: String, action: Action) {
        self.rootPassword = rootPassword
        self.action = action
    }
}

/// `{"wss_url", "password", "action"}` shape returned by `requestConsole`.
/// `password` is a secret.
public struct ConsoleResult: Decodable, Sendable, Equatable {
    public let wssURL: URL
    public let password: String
    public let action: Action

    enum CodingKeys: String, CodingKey {
        case wssURL = "wss_url"
        case password
        case action
    }

    public init(wssURL: URL, password: String, action: Action) {
        self.wssURL = wssURL
        self.password = password
        self.action = action
    }
}

/// `{"image", "action"}` shape returned by `createImage`.
public struct CreatedImage: Decodable, Sendable, Equatable {
    public let image: Image
    public let action: Action

    enum CodingKeys: String, CodingKey { case image, action }

    public init(image: Image, action: Action) {
        self.image = image
        self.action = action
    }
}
