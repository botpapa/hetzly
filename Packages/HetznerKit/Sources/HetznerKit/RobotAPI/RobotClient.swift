import Foundation

// MARK: - Serialization primitive

/// A one-permit async mutex. `RobotClient` uses this to guarantee at most
/// one HTTP request is ever in flight at a time, even though actor
/// reentrancy would otherwise let two overlapping calls both reach their
/// `await transport.data(for:)` suspension point concurrently. Hetzner Robot
/// documents a hard 3-failed-login IP ban, so overlapping/racing requests
/// (which could re-order and duplicate retries around a bad-credentials
/// response) are treated as unacceptable, not just wasteful.
///
/// Implemented as its own actor (not a lock) so `acquire()`/`release()` are
/// themselves safe to call concurrently without `@unchecked Sendable`.
actor RobotRequestGate {
    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Suspends until this call holds the single permit.
    func acquire() async {
        if !isHeld {
            isHeld = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Releases the permit, handing it directly to the next waiter (if any)
    /// rather than resetting `isHeld` — this keeps the permit continuously
    /// held so a third caller can't slip in between release and hand-off.
    func release() {
        guard !waiters.isEmpty else {
            isHeld = false
            return
        }
        let next = waiters.removeFirst()
        next.resume()
    }
}

// MARK: - Form encoding

/// Builds `application/x-www-form-urlencoded` request bodies for Robot's
/// POST/PUT endpoints (Robot does not accept JSON bodies). Percent-encoding
/// is delegated to `URLComponents`/`URLQueryItem` — the same machinery
/// `URLRequest` query strings use elsewhere in this package — so encoding
/// stays consistent rather than reinventing RFC 3986 escaping. Repeated keys
/// (e.g. `authorized_key[]`) are supported since the input is an ordered
/// array, not a dictionary.
enum RobotFormEncoder {
    static func encode(_ items: [URLQueryItem]) -> Data {
        var components = URLComponents()
        components.queryItems = items
        return Data((components.percentEncodedQuery ?? "").utf8)
    }
}

// MARK: - Wrapped-response decoding

/// Robot wraps every response object under a key named after the resource
/// (`{"server": {...}}`), and wraps each element of list responses the same
/// way (`[{"server": {...}}, ...]`). These helpers decode through that
/// wrapper generically instead of requiring a bespoke `Envelope` type per
/// model. `key` is used to pick the right value when a response
/// unexpectedly carries more than one top-level key; when exactly one key is
/// present (the normal case) it's used directly.
enum RobotDecoding {
    static func decodeWrapped<T: Decodable & Sendable>(
        key: String,
        from data: Data,
        using decoder: JSONDecoder
    ) throws -> T {
        do {
            let dict = try decoder.decode([String: T].self, from: data)
            if let value = dict[key] { return value }
            if let value = dict.values.first { return value }
            throw HetznerAPIError.decoding(underlying: "Robot response is missing the \"\(key)\" wrapper key.")
        } catch let error as HetznerAPIError {
            throw error
        } catch {
            throw HetznerAPIError.decoding(underlying: String(describing: error))
        }
    }

    static func decodeWrappedList<T: Decodable & Sendable>(
        key: String,
        from data: Data,
        using decoder: JSONDecoder
    ) throws -> [T] {
        do {
            let array = try decoder.decode([[String: T]].self, from: data)
            return try array.map { element in
                if let value = element[key] { return value }
                if let value = element.values.first { return value }
                throw HetznerAPIError.decoding(underlying: "Robot list element is missing the \"\(key)\" wrapper key.")
            }
        } catch let error as HetznerAPIError {
            throw error
        } catch {
            throw HetznerAPIError.decoding(underlying: String(describing: error))
        }
    }
}

// MARK: - Error envelope

/// Robot's error envelope: `{"error": {"status": 404, "code": "...",
/// "message": "..."}}`. Distinct from `HetznerErrorEnvelope` (Core) because
/// Robot additionally echoes the HTTP status inside the body.
struct RobotErrorEnvelope: Decodable {
    struct Body: Decodable {
        let status: Int?
        let code: String
        let message: String
    }
    let error: Body
}

/// High-level client for the Hetzner Robot Webservice (dedicated servers).
/// Robot is a much stricter API than Cloud: HTTP Basic auth over a
/// per-account username/password (not a token), a documented 3-failed-login
/// IP ban, and no documented rate-limit response headers to react to — so
/// this client is conservative by construction rather than reactive:
///
/// - **Serialized**: every request funnels through `RobotRequestGate` so
///   exactly one HTTP call is in flight at a time.
/// - **Budgeted**: a `RateLimiter(budget: 150, window: 3600)` throttles
///   proactively instead of waiting to be told to slow down.
/// - **Cached**: `GET /server`, `/ip`, `/subnet`, and `/key` responses are
///   cached in memory for 5 minutes; every other GET (rescue/boot/reset/
///   rdns) is never cached, because those can carry passwords or change as
///   a side effect of merely being read.
/// - **Never retries a 401**: a bad Basic-auth attempt counts toward
///   Robot's IP ban, so no code path here re-issues a request after seeing
///   one (the `setRDNS` POST→PUT fallback only triggers on an
///   already-exists conflict, never on 401).
public actor RobotClient {
    // Shared plumbing is `internal` (not `private`) rather than file-scoped,
    // so `extension RobotClient` files added elsewhere in this target (the
    // M3 ordering endpoints — `RobotAPI/Ordering*.swift`) can reuse the same
    // gated/rate-limited/cached request path instead of re-implementing it.
    // Mirrors the documented precedent in `CloudClient.swift`.
    let transport: HTTPTransport
    let auth: AuthMethod
    let rateLimiter: RateLimiter
    let decoder: JSONDecoder
    let gate = RobotRequestGate()

    private static let baseURL = URL(string: "https://robot-ws.your-server.de")!
    private static let cacheTTL: TimeInterval = 300
    private static let cacheablePathPrefixes = ["/server", "/ip", "/subnet", "/key"]

    private var cacheStorage: [String: (data: Data, storedAt: ContinuousClock.Instant)] = [:]
    private let clock = ContinuousClock()

    public init(username: String, password: String, transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
        self.auth = .basic(username: username, password: password)
        self.rateLimiter = RateLimiter(budget: 150, window: 3600)
        self.decoder = JSONDecoder()
    }

    // MARK: - Public API

    /// Confirms the configured credentials are accepted. Issues EXACTLY one
    /// `GET /server` (cache is bypassed so this always makes a real network
    /// round trip); throws `HetznerAPIError.unauthorized` on a 401 and never
    /// retries.
    public func validateCredentials() async throws {
        _ = try await cachedGET(path: "/server", forceRefresh: true) as Data
    }

    public func listServers(forceRefresh: Bool = false) async throws -> [RobotServer] {
        let data = try await cachedGET(path: "/server", forceRefresh: forceRefresh)
        return try RobotDecoding.decodeWrappedList(key: "server", from: data, using: decoder)
    }

    public func server(number: Int) async throws -> RobotServer {
        let data = try await cachedGET(path: "/server/\(number)", forceRefresh: false)
        return try RobotDecoding.decodeWrapped(key: "server", from: data, using: decoder)
    }

    /// `POST /server/{n}` with `server_name=...`. Invalidates the cached
    /// list and single-server entries for this server so a subsequent read
    /// doesn't serve the stale name.
    public func rename(serverNumber: Int, to name: String) async throws -> RobotServer {
        let body = [URLQueryItem(name: "server_name", value: name)]
        let data = try await execute(method: .post, path: "/server/\(serverNumber)", formBody: body)
        invalidateCache(exactPath: "/server")
        invalidateCache(exactPath: "/server/\(serverNumber)")
        return try RobotDecoding.decodeWrapped(key: "server", from: data, using: decoder)
    }

    /// `GET /reset/{n}` — never cached (operating status is live data).
    public func resetOptions(serverNumber: Int) async throws -> RobotResetInfo {
        let data = try await execute(method: .get, path: "/reset/\(serverNumber)")
        return try RobotDecoding.decodeWrapped(key: "reset", from: data, using: decoder)
    }

    /// `POST /reset/{n}` with `type=sw|hw|man`.
    public func reset(serverNumber: Int, type: RobotResetType) async throws {
        let body = [URLQueryItem(name: "type", value: type.rawValue)]
        _ = try await execute(method: .post, path: "/reset/\(serverNumber)", formBody: body)
    }

    /// `POST /wol/{n}` — Wake-on-LAN.
    public func wake(serverNumber: Int) async throws {
        _ = try await execute(method: .post, path: "/wol/\(serverNumber)")
    }

    /// `GET /boot/{n}/rescue` — never cached; the response can carry a
    /// still-secret one-time password.
    public func rescue(serverNumber: Int) async throws -> RobotRescue {
        let data = try await execute(method: .get, path: "/boot/\(serverNumber)/rescue")
        return try RobotDecoding.decodeWrapped(key: "rescue", from: data, using: decoder)
    }

    /// `POST /boot/{n}/rescue` with `os=...` and one `authorized_key[]=...`
    /// per fingerprint. The response carries a freshly generated root
    /// password — SECRET, never logged.
    public func enableRescue(serverNumber: Int, os: String, sshKeyFingerprints: [String]) async throws -> RobotRescue {
        var body = [URLQueryItem(name: "os", value: os)]
        body.append(contentsOf: sshKeyFingerprints.map { URLQueryItem(name: "authorized_key[]", value: $0) })
        let data = try await execute(method: .post, path: "/boot/\(serverNumber)/rescue", formBody: body)
        return try RobotDecoding.decodeWrapped(key: "rescue", from: data, using: decoder)
    }

    /// `DELETE /boot/{n}/rescue`.
    public func disableRescue(serverNumber: Int) async throws -> RobotRescue {
        let data = try await execute(method: .delete, path: "/boot/\(serverNumber)/rescue")
        return try RobotDecoding.decodeWrapped(key: "rescue", from: data, using: decoder)
    }

    /// `GET /boot/{n}` — never cached, same rationale as `rescue(serverNumber:)`.
    public func bootConfiguration(serverNumber: Int) async throws -> RobotBootConfiguration {
        let data = try await execute(method: .get, path: "/boot/\(serverNumber)")
        return try RobotDecoding.decodeWrapped(key: "boot", from: data, using: decoder)
    }

    /// `GET /rdns/{ip}` — never cached.
    public func rdns(ip: String) async throws -> RobotRDNS {
        let data = try await execute(method: .get, path: "/rdns/\(ip)")
        return try RobotDecoding.decodeWrapped(key: "rdns", from: data, using: decoder)
    }

    /// Creates or updates the PTR record for `ip`. Robot exposes separate
    /// create (`POST`) and update (`PUT`) endpoints for the same resource;
    /// rather than requiring callers to know which state the record is
    /// already in, this tries `POST` first and falls back to `PUT` only
    /// when the server reports the record already exists (a 400/409
    /// "already exists" style error) — never on any other failure, and
    /// never in response to a 401.
    public func setRDNS(ip: String, ptr: String) async throws -> RobotRDNS {
        let body = [URLQueryItem(name: "ptr", value: ptr)]
        do {
            let data = try await execute(method: .post, path: "/rdns/\(ip)", formBody: body)
            return try RobotDecoding.decodeWrapped(key: "rdns", from: data, using: decoder)
        } catch {
            guard Self.isAlreadyExistsConflict(error) else { throw error }
            let data = try await execute(method: .put, path: "/rdns/\(ip)", formBody: body)
            return try RobotDecoding.decodeWrapped(key: "rdns", from: data, using: decoder)
        }
    }

    /// `DELETE /rdns/{ip}`.
    public func deleteRDNS(ip: String) async throws {
        _ = try await execute(method: .delete, path: "/rdns/\(ip)")
    }

    public func listIPs() async throws -> [RobotIP] {
        let data = try await cachedGET(path: "/ip", forceRefresh: false)
        return try RobotDecoding.decodeWrappedList(key: "ip", from: data, using: decoder)
    }

    public func listSubnets() async throws -> [RobotSubnet] {
        let data = try await cachedGET(path: "/subnet", forceRefresh: false)
        return try RobotDecoding.decodeWrappedList(key: "subnet", from: data, using: decoder)
    }

    public func listSSHKeys() async throws -> [RobotSSHKey] {
        let data = try await cachedGET(path: "/key", forceRefresh: false)
        return try RobotDecoding.decodeWrappedList(key: "key", from: data, using: decoder)
    }

    // MARK: - Request execution (shared with ordering extensions)

    /// Runs a GET through the 5-minute cache when `path` is one of the
    /// cacheable resources (`/server`, `/ip`, `/subnet`, `/key`); every
    /// other path always hits the network. `forceRefresh` bypasses a cache
    /// hit but still populates the cache with the fresh response.
    func cachedGET(path: String, forceRefresh: Bool) async throws -> Data {
        let cacheable = Self.isCacheable(path: path)
        let key = "GET \(path)"

        if cacheable, !forceRefresh, let cached = lookupCache(key) {
            return cached
        }

        let data = try await execute(method: .get, path: path)

        if cacheable {
            cacheStorage[key] = (data, clock.now)
        }
        return data
    }

    /// Sends one HTTP request through the serialization gate and the rate
    /// limiter, and maps non-2xx responses to `HetznerAPIError`. This is the
    /// single choke point every public method (and every ordering
    /// extension) funnels through — it's what makes "one in flight at a
    /// time" and "~150/h budget" true for the whole client, not just the
    /// cached-GET path.
    func execute(
        method: HTTPMethod,
        path: String,
        query: [URLQueryItem] = [],
        formBody: [URLQueryItem]? = nil
    ) async throws -> Data {
        await rateLimiter.waitForSlot()
        await gate.acquire()

        let outcome: Result<(Data, HTTPURLResponse), Error>
        do {
            let request = try makeRequest(method: method, path: path, query: query, formBody: formBody)
            outcome = .success(try await transport.data(for: request))
        } catch {
            outcome = .failure(error)
        }

        await gate.release()

        switch outcome {
        case .success(let (data, response)):
            await rateLimiter.record(response: response)
            guard (200..<300).contains(response.statusCode) else {
                throw Self.mapError(status: response.statusCode, data: data, response: response)
            }
            return data
        case .failure(let error):
            if let apiError = error as? HetznerAPIError { throw apiError }
            throw HetznerAPIError.transport(underlying: error.localizedDescription)
        }
    }

    // MARK: - Request building

    private func makeRequest(
        method: HTTPMethod,
        path: String,
        query: [URLQueryItem],
        formBody: [URLQueryItem]?
    ) throws -> URLRequest {
        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let url = Self.baseURL.appendingPathComponent(trimmedPath)

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw HetznerAPIError.transport(underlying: "Failed to construct a valid Robot request URL.")
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let finalURL = components.url else {
            throw HetznerAPIError.transport(underlying: "Failed to construct a valid Robot request URL.")
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(auth.headerValue, forHTTPHeaderField: "Authorization")

        if let formBody {
            request.httpBody = RobotFormEncoder.encode(formBody)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    // MARK: - Cache helpers

    private func lookupCache(_ key: String) -> Data? {
        guard let entry = cacheStorage[key] else { return nil }
        if elapsedSeconds(since: entry.storedAt) > Self.cacheTTL {
            cacheStorage[key] = nil
            return nil
        }
        return entry.data
    }

    private func invalidateCache(exactPath path: String) {
        cacheStorage["GET \(path)"] = nil
    }

    private func elapsedSeconds(since instant: ContinuousClock.Instant) -> TimeInterval {
        let elapsed = clock.now - instant
        let components = elapsed.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    private static func isCacheable(path: String) -> Bool {
        cacheablePathPrefixes.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    // MARK: - Error mapping

    static func mapError(status: Int, data: Data, response: HTTPURLResponse) -> HetznerAPIError {
        let envelope = try? JSONDecoder().decode(RobotErrorEnvelope.self, from: data).error

        switch status {
        case 401:
            return .unauthorized
        case 403:
            if let envelope {
                return .forbidden(message: "\(envelope.code): \(envelope.message)")
            }
            return .forbidden(message: nil)
        case 404:
            return .notFound
        case 429:
            return .rateLimited(retryAfter: retryAfterInterval(from: response))
        default:
            if let envelope {
                if envelope.code == "RATE_LIMIT_EXCEEDED" {
                    return .rateLimited(retryAfter: retryAfterInterval(from: response))
                }
                return .api(code: envelope.code, message: envelope.message)
            }
            return .http(status: status)
        }
    }

    private static func retryAfterInterval(from response: HTTPURLResponse) -> TimeInterval? {
        guard let header = response.value(forHTTPHeaderField: "Retry-After"), let seconds = TimeInterval(header) else {
            return nil
        }
        return seconds
    }

    private static func isAlreadyExistsConflict(_ error: Error) -> Bool {
        switch error {
        case HetznerAPIError.api(let code, _):
            return code.uppercased().contains("ALREADY_EXISTS")
        case HetznerAPIError.http(let status):
            return status == 409
        default:
            return false
        }
    }
}
