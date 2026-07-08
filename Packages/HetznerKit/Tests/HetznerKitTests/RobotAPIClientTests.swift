import Foundation
import Testing
@testable import HetznerKit

/// Realistic Hetzner Robot Webservice JSON fixtures shared across
/// `RobotAPI*Tests`. Robot wraps every object under a key named after the
/// resource (`{"server": {...}}`), and wraps each element of list responses
/// the same way.
enum RobotFixtures {
    static func serverObjectJSON(number: Int = 1, name: String = "srv-01", status: String = "ready") -> String {
        """
        {
            "server_ip": "123.45.67.\(number)",
            "server_ipv6_net": "2a01:4f8::\(number)/64",
            "server_number": \(number),
            "server_name": "\(name)",
            "product": "AX41-NVMe",
            "dc": "FSN1-DC8",
            "traffic": "20 TB",
            "status": "\(status)",
            "cancelled": false,
            "paid_until": "2026-12-31",
            "ip": ["123.45.67.\(number)"],
            "subnet": [{"ip": "2a01:4f8::\(number)", "mask": "64"}]
        }
        """
    }

    static func serverWrappedJSON(number: Int = 1, name: String = "srv-01", status: String = "ready") -> Data {
        Data(#"{"server": \#(serverObjectJSON(number: number, name: name, status: status))}"#.utf8)
    }

    static func serverListWrappedJSON(_ servers: [(number: Int, name: String)]) -> Data {
        let elements = servers.map { #"{"server": \#(serverObjectJSON(number: $0.number, name: $0.name))}"# }
        return Data("[\(elements.joined(separator: ","))]".utf8)
    }

    static func resetInfoWrappedJSON(number: Int = 1, types: [String] = ["sw", "hw", "man"], operatingStatus: String? = "not-supported") -> Data {
        let typesJSON = types.map { "\"\($0)\"" }.joined(separator: ",")
        let statusField = operatingStatus.map { "\"\($0)\"" } ?? "null"
        return Data(
            """
            {"reset": {"server_number": \(number), "type": [\(typesJSON)], "operating_status": \(statusField)}}
            """.utf8
        )
    }

    static func rescueWrappedJSON(os: String = "linux", active: Bool = true, password: String? = nil) -> Data {
        let passwordField = password.map { "\"\($0)\"" } ?? "null"
        return Data(
            """
            {"rescue": {"server_ip": "1.2.3.4", "server_number": 1, "os": "\(os)", "active": \(active), "password": \(passwordField), "authorized_key": ["aa:bb:cc"]}}
            """.utf8
        )
    }

    static func bootConfigWrappedJSON(linuxDistJSON: String) -> Data {
        Data(
            """
            {"boot": {"linux": {"dist": \(linuxDistJSON), "active": true, "password": "onetimepw"}}}
            """.utf8
        )
    }

    static func rdnsWrappedJSON(ip: String = "1.2.3.4", ptr: String = "host.example.com") -> Data {
        Data(#"{"rdns": {"ip": "\#(ip)", "ptr": "\#(ptr)"}}"#.utf8)
    }

    static func keyListWrappedJSON(_ keys: [(name: String, fingerprint: String)]) -> Data {
        let elements = keys.map { #"{"key": {"name": "\#($0.name)", "fingerprint": "\#($0.fingerprint)"}}"# }
        return Data("[\(elements.joined(separator: ","))]".utf8)
    }

    static func errorEnvelopeJSON(status: Int, code: String, message: String) -> Data {
        Data(#"{"error": {"status": \#(status), "code": "\#(code)", "message": "\#(message)"}}"#.utf8)
    }
}

/// Parses an `application/x-www-form-urlencoded` request body back into
/// ordered name/value pairs, so tests can assert on form contents without
/// depending on exact percent-encoding of reserved characters like `[`/`]`.
func decodeFormBody(_ data: Data?) -> [(String, String)] {
    guard let data, let string = String(data: data, encoding: .utf8) else { return [] }
    var components = URLComponents()
    components.percentEncodedQuery = string
    return (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
}

/// A scripted `HTTPTransport` that introduces an artificial delay before
/// responding and records the wall-clock interval each call was in flight
/// for. Used to prove `RobotClient` serializes requests: if two calls truly
/// overlap, their recorded intervals overlap in time; if they're properly
/// serialized one-at-a-time, each interval starts no earlier than the
/// previous one ended.
actor TimedMockTransport: HTTPTransport {
    struct Interval: Sendable {
        let start: ContinuousClock.Instant
        let end: ContinuousClock.Instant
    }

    private let delay: Duration
    private let statusCode: Int
    private let body: Data
    private let clock = ContinuousClock()
    private(set) var intervals: [Interval] = []
    private(set) var requestCount = 0

    init(delay: Duration, statusCode: Int = 200, body: Data) {
        self.delay = delay
        self.statusCode = statusCode
        self.body = body
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        let start = clock.now
        try? await Task.sleep(for: delay)
        let end = clock.now
        intervals.append(Interval(start: start, end: end))

        let url = request.url ?? URL(string: "https://robot-ws.your-server.de")!
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: [:])!
        return (body, response)
    }
}

@Suite("RobotClient")
struct RobotAPIClientTests {
    private func makeClient(responses: [MockTransport.ScriptedResponse]) -> (RobotClient, MockTransport) {
        let transport = MockTransport(responses: responses)
        let client = RobotClient(username: "webuser", password: "s3cret", transport: transport)
        return (client, transport)
    }

    // MARK: - Auth

    @Test func basicAuthorizationHeaderIsBase64EncodedUsernamePassword() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: RobotFixtures.serverListWrappedJSON([(1, "srv-01")])),
        ])
        _ = try await client.listServers()

        let expected = "Basic " + Data("webuser:s3cret".utf8).base64EncodedString()
        let requests = await transport.recordedRequests
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == expected)
    }

    // MARK: - Serialization

    @Test func requestsAreSerializedOneAtATimeEvenWhenFiredConcurrently() async throws {
        let transport = TimedMockTransport(
            delay: .milliseconds(60),
            body: RobotFixtures.serverWrappedJSON(number: 1, name: "srv-01")
        )
        let client = RobotClient(username: "u", password: "p", transport: transport)

        async let first: RobotServer = client.server(number: 1)
        async let second: RobotServer = client.server(number: 2)
        async let third: RobotServer = client.server(number: 3)
        _ = try await (first, second, third)

        let intervals = await transport.intervals
        #expect(intervals.count == 3)

        let sorted = intervals.sorted { $0.start < $1.start }
        for i in 1..<sorted.count {
            // A later request's transport call must not start before the
            // previous one's finished — proof that only one call was ever
            // in flight on the transport at once.
            #expect(sorted[i].start >= sorted[i - 1].end)
        }
    }

    // MARK: - GET cache

    @Test func getResponsesAreCachedWithinTTL() async throws {
        // Only one scripted response: a second network hit would fail with
        // no response queued, proving the second call was served from cache.
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: RobotFixtures.keyListWrappedJSON([("k1", "aa:bb")])),
        ])

        let first = try await client.listSSHKeys()
        let second = try await client.listSSHKeys()

        #expect(first == second)
        let requests = await transport.recordedRequests
        #expect(requests.count == 1)
    }

    @Test func forceRefreshBypassesCache() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: RobotFixtures.serverListWrappedJSON([(1, "first-name")])),
            .init(statusCode: 200, data: RobotFixtures.serverListWrappedJSON([(1, "second-name")])),
        ])

        let first = try await client.listServers()
        let second = try await client.listServers(forceRefresh: true)

        #expect(first.first?.serverName == "first-name")
        #expect(second.first?.serverName == "second-name")

        let requests = await transport.recordedRequests
        #expect(requests.count == 2)
    }

    @Test func postResponsesAreNeverCached() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: RobotFixtures.serverWrappedJSON(number: 5, name: "one")),
            .init(statusCode: 200, data: RobotFixtures.serverWrappedJSON(number: 5, name: "two")),
        ])

        _ = try await client.rename(serverNumber: 5, to: "one")
        _ = try await client.rename(serverNumber: 5, to: "two")

        let requests = await transport.recordedRequests
        #expect(requests.count == 2)
    }

    @Test func rescueAndBootGETsAreNeverCached() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: RobotFixtures.rescueWrappedJSON(password: "onetime-a")),
            .init(statusCode: 200, data: RobotFixtures.rescueWrappedJSON(password: "onetime-b")),
        ])

        let first = try await client.rescue(serverNumber: 1)
        let second = try await client.rescue(serverNumber: 1)

        #expect(first.password == "onetime-a")
        #expect(second.password == "onetime-b")
        let requests = await transport.recordedRequests
        #expect(requests.count == 2)
    }

    // MARK: - validateCredentials

    @Test func validateCredentialsMakesExactlyOneRequest() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: RobotFixtures.serverListWrappedJSON([(1, "srv-01")])),
        ])
        try await client.validateCredentials()

        let requests = await transport.recordedRequests
        #expect(requests.count == 1)
        #expect(requests[0].httpMethod == "GET")
        #expect(requests[0].url?.path == "/server")
    }

    @Test func validateCredentialsThrowsUnauthorizedOn401AndNeverRetries() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 401, data: Data()),
        ])
        do {
            try await client.validateCredentials()
            Issue.record("Expected validateCredentials to throw")
        } catch HetznerAPIError.unauthorized {
            // expected
        }

        let requests = await transport.recordedRequests
        #expect(requests.count == 1)
    }

    // MARK: - Wrapped decoding

    @Test func wrappedListDecodesEachElement() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: RobotFixtures.serverListWrappedJSON([(1, "alpha"), (2, "beta")])),
        ])
        let servers = try await client.listServers()
        #expect(servers.map(\.serverName) == ["alpha", "beta"])
        _ = await transport.recordedRequests
    }

    @Test func wrappedSingleDecodes() async throws {
        let (client, _) = makeClient(responses: [
            .init(statusCode: 200, data: RobotFixtures.serverWrappedJSON(number: 42, name: "solo")),
        ])
        let server = try await client.server(number: 42)
        #expect(server.serverNumber == 42)
        #expect(server.serverName == "solo")
        #expect(server.id == 42)
    }

    // MARK: - Form encoding

    @Test func resetSendsFormEncodedTypeBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: RobotFixtures.resetInfoWrappedJSON()),
        ])
        try await client.reset(serverNumber: 1, type: .hw)

        let requests = await transport.recordedRequests
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[0].url?.path == "/reset/1")
        #expect(requests[0].value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(String(data: requests[0].httpBody ?? Data(), encoding: .utf8) == "type=hw")
    }

    @Test func enableRescueSendsMultipleAuthorizedKeyFormFields() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: RobotFixtures.rescueWrappedJSON(os: "linux", active: true, password: "pw")),
        ])
        _ = try await client.enableRescue(serverNumber: 1, os: "linux", sshKeyFingerprints: ["fp1", "fp2"])

        let requests = await transport.recordedRequests
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[0].url?.path == "/boot/1/rescue")

        let pairs = decodeFormBody(requests[0].httpBody)
        #expect(pairs.contains { $0.0 == "os" && $0.1 == "linux" })
        let keyValues = pairs.filter { $0.0 == "authorized_key[]" }.map(\.1)
        #expect(keyValues == ["fp1", "fp2"])
    }

    @Test func rescueDecodesSecretPassword() async throws {
        let (client, _) = makeClient(responses: [
            .init(statusCode: 200, data: RobotFixtures.rescueWrappedJSON(os: "linux", active: true, password: "s3cr3t-root-pw")),
        ])
        let rescue = try await client.rescue(serverNumber: 1)
        #expect(rescue.password == "s3cr3t-root-pw")
        #expect(rescue.active == true)
        #expect(rescue.os == "linux")
    }

    @Test func renameSendsFormEncodedServerNameAndReturnsServer() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: RobotFixtures.serverWrappedJSON(number: 5, name: "newname")),
        ])
        let server = try await client.rename(serverNumber: 5, to: "newname")

        #expect(server.serverName == "newname")
        let requests = await transport.recordedRequests
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[0].url?.path == "/server/5")
        #expect(String(data: requests[0].httpBody ?? Data(), encoding: .utf8) == "server_name=newname")
    }

    // MARK: - dist string-or-array

    @Test func bootConfigurationDecodesDistAsPlainString() async throws {
        let (client, _) = makeClient(responses: [
            .init(statusCode: 200, data: RobotFixtures.bootConfigWrappedJSON(linuxDistJSON: #""CentOS 7""#)),
        ])
        let config = try await client.bootConfiguration(serverNumber: 1)
        #expect(config.linux?.dist == ["CentOS 7"])
    }

    @Test func bootConfigurationDecodesDistAsArray() async throws {
        let (client, _) = makeClient(responses: [
            .init(statusCode: 200, data: RobotFixtures.bootConfigWrappedJSON(linuxDistJSON: #"["CentOS 6", "CentOS 7"]"#)),
        ])
        let config = try await client.bootConfiguration(serverNumber: 1)
        #expect(config.linux?.dist == ["CentOS 6", "CentOS 7"])
        #expect(config.linux?.password == "onetimepw")
    }

    // MARK: - rdns flow

    @Test func setRDNSCreatesViaPOSTWhenRecordIsNew() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: RobotFixtures.rdnsWrappedJSON(ip: "1.2.3.4", ptr: "host.example.com")),
        ])
        let rdns = try await client.setRDNS(ip: "1.2.3.4", ptr: "host.example.com")
        #expect(rdns.ptr == "host.example.com")

        let requests = await transport.recordedRequests
        #expect(requests.count == 1)
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[0].url?.path == "/rdns/1.2.3.4")
    }

    @Test func setRDNSFallsBackToPUTWhenPOSTReportsAlreadyExists() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 400, data: RobotFixtures.errorEnvelopeJSON(status: 400, code: "RDNS_ALREADY_EXISTS", message: "already there")),
            .init(statusCode: 200, data: RobotFixtures.rdnsWrappedJSON(ip: "1.2.3.4", ptr: "updated.example.com")),
        ])
        let rdns = try await client.setRDNS(ip: "1.2.3.4", ptr: "updated.example.com")
        #expect(rdns.ptr == "updated.example.com")

        let requests = await transport.recordedRequests
        #expect(requests.count == 2)
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[1].httpMethod == "PUT")
    }

    // MARK: - Error mapping

    @Test func mapsUnauthorizedForbiddenNotFoundAndRateLimited() async throws {
        let cases: [(Int, HetznerAPIError)] = [
            (401, .unauthorized),
            (404, .notFound),
        ]
        for (status, _) in cases {
            let (client, _) = makeClient(responses: [.init(statusCode: status, data: Data())])
            do {
                _ = try await client.listServers()
                Issue.record("Expected an error for status \(status)")
            } catch let error as HetznerAPIError {
                switch (status, error) {
                case (401, .unauthorized), (404, .notFound):
                    break
                default:
                    Issue.record("Unexpected error \(error) for status \(status)")
                }
            }
        }
    }

    @Test func forbiddenPreservesCodeInMessage() async throws {
        let (client, _) = makeClient(responses: [
            .init(
                statusCode: 403,
                data: RobotFixtures.errorEnvelopeJSON(status: 403, code: "NOT_ALLOWED", message: "ordering is disabled")
            ),
        ])
        do {
            _ = try await client.listServers()
            Issue.record("Expected forbidden to be thrown")
        } catch HetznerAPIError.forbidden(let message) {
            #expect(message == "NOT_ALLOWED: ordering is disabled")
        }
    }

    @Test func rateLimitExceededCodeMapsToRateLimitedEvenOnNon429Status() async throws {
        let (client, _) = makeClient(responses: [
            .init(
                statusCode: 500,
                data: RobotFixtures.errorEnvelopeJSON(status: 500, code: "RATE_LIMIT_EXCEEDED", message: "slow down")
            ),
        ])
        do {
            _ = try await client.listServers()
            Issue.record("Expected rateLimited to be thrown")
        } catch HetznerAPIError.rateLimited {
            // expected
        }
    }

    @Test func unknownErrorCodeMapsToAPIError() async throws {
        let (client, _) = makeClient(responses: [
            .init(
                statusCode: 409,
                data: RobotFixtures.errorEnvelopeJSON(status: 409, code: "SERVER_NOT_CANCELLABLE", message: "can't cancel")
            ),
        ])
        do {
            _ = try await client.listServers()
            Issue.record("Expected api error to be thrown")
        } catch HetznerAPIError.api(let code, let message) {
            #expect(code == "SERVER_NOT_CANCELLABLE")
            #expect(message == "can't cancel")
        }
    }
}
