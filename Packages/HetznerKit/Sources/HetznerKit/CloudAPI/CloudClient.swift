import Foundation

/// Metric families available from `GET /servers/{id}/metrics`.
public enum MetricsType: String, Sendable, CaseIterable {
    case cpu, disk, network
}

/// High-level client for the Hetzner Cloud API v1. Composes the shared
/// `HetznerHTTPClient` with a conservative rate-limit budget (Hetzner's
/// documented default is 3600 requests/hour per token).
public actor CloudClient {
    private let client: HetznerHTTPClient

    /// Fixed, well-formed literal — not user-controlled input, so the
    /// force-unwrap can never fail.
    private static let baseURL = URL(string: "https://api.hetzner.cloud/v1")!

    public init(token: String, transport: HTTPTransport = URLSessionTransport()) {
        let configuration = APIConfiguration(baseURL: Self.baseURL, auth: .bearer(token: token))
        self.client = HetznerHTTPClient(
            configuration: configuration,
            transport: transport,
            rateLimiter: RateLimiter(budget: 3600, window: 3600)
        )
    }

    /// Cheap authenticated GET (`/pricing`, read-scope-safe) to confirm the
    /// token is accepted. Throws `HetznerAPIError.unauthorized` on a bad token.
    public func validateToken() async throws {
        _ = try await pricing()
    }

    /// All servers, fully paginated and sorted by name (case-insensitive).
    public func listServers() async throws -> [Server] {
        let stream: AsyncThrowingStream<[Server], Error> = paginated(
            client: client,
            endpoint: Endpoint(path: "/servers"),
            itemsKey: "servers",
            perPage: 50
        )

        var servers: [Server] = []
        for try await page in stream {
            servers.append(contentsOf: page)
        }
        return servers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func server(id: Int) async throws -> Server {
        let envelope: ServerEnvelope = try await client.send(Endpoint(path: "/servers/\(id)"))
        return envelope.server
    }

    /// Hetzner returns `{"action": ...}` for server deletion, not 204.
    public func deleteServer(id: Int) async throws -> Action {
        try await performServerAction(Endpoint(method: .delete, path: "/servers/\(id)"))
    }

    public func powerOn(serverID: Int) async throws -> Action {
        try await performServerAction(Endpoint(method: .post, path: "/servers/\(serverID)/actions/poweron"))
    }

    /// Hard power off (immediate, no ACPI shutdown sequence).
    public func powerOff(serverID: Int) async throws -> Action {
        try await performServerAction(Endpoint(method: .post, path: "/servers/\(serverID)/actions/poweroff"))
    }

    /// ACPI shutdown request — the guest OS may take time to comply.
    public func shutdown(serverID: Int) async throws -> Action {
        try await performServerAction(Endpoint(method: .post, path: "/servers/\(serverID)/actions/shutdown"))
    }

    /// Soft reboot.
    public func reboot(serverID: Int) async throws -> Action {
        try await performServerAction(Endpoint(method: .post, path: "/servers/\(serverID)/actions/reboot"))
    }

    /// Hard reset.
    public func reset(serverID: Int) async throws -> Action {
        try await performServerAction(Endpoint(method: .post, path: "/servers/\(serverID)/actions/reset"))
    }

    public func action(id: Int) async throws -> Action {
        let envelope: ActionEnvelope = try await client.send(Endpoint(path: "/actions/\(id)"))
        return envelope.action
    }

    public func serverMetrics(
        serverID: Int,
        types: Set<MetricsType>,
        start: Date,
        end: Date,
        step: TimeInterval
    ) async throws -> ServerMetrics {
        let typeParam = types.map(\.rawValue).sorted().joined(separator: ",")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let query = [
            URLQueryItem(name: "type", value: typeParam),
            URLQueryItem(name: "start", value: formatter.string(from: start)),
            URLQueryItem(name: "end", value: formatter.string(from: end)),
            URLQueryItem(name: "step", value: String(Int(step))),
        ]
        return try await client.send(Endpoint(path: "/servers/\(serverID)/metrics", query: query))
    }

    /// Callers should cache this (~24h) via `ResponseCache` — pricing rarely
    /// changes and this is a comparatively heavy response.
    public func pricing() async throws -> Pricing {
        try await client.send(Endpoint(path: "/pricing"))
    }

    private func performServerAction(_ endpoint: Endpoint) async throws -> Action {
        let envelope: ActionEnvelope = try await client.send(endpoint)
        return envelope.action
    }
}
