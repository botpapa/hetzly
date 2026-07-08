import Foundation
import Testing
@testable import HetznerKit

/// Fixtures local to this file.
///
/// The vSwitch JSON shapes here are taken from a real Robot API
/// request/response round-trip captured in a maintained third-party Robot
/// client's test suite (a `#[derive(Deserialize)]` struct with a passing
/// unit test asserting it decodes this exact payload) — Robot's own prose
/// docs describe the fields but don't show a verbatim example. The failover
/// JSON shape is quoted directly from Robot's official webservice
/// documentation (`https://robot.hetzner.com/doc/webservice/en.html`),
/// which shows the wrapped `{"failover": {...}}` example inline.
private enum VSwitchFailoverFixtures {
    /// List shape from `GET /vswitch`: a plain (unwrapped) array; each
    /// element has only the four scalar fields, no nested arrays at all.
    static func vSwitchListJSON(entries: [(id: Int, name: String, vlan: Int, cancelled: Bool)]) -> Data {
        let items = entries.map(vSwitchListShapeObjectJSON).joined(separator: ",")
        return Data("[\(items)]".utf8)
    }

    /// A single list-shape object (no nested arrays), as returned by
    /// `POST /vswitch` (create) and `POST /vswitch/{id}` (update) — both
    /// answer with one plain vSwitch object, not an array.
    static func vSwitchSingleListShapeJSON(id: Int, name: String, vlan: Int, cancelled: Bool = false) -> Data {
        Data(vSwitchListShapeObjectJSON((id: id, name: name, vlan: vlan, cancelled: cancelled)).utf8)
    }

    private static func vSwitchListShapeObjectJSON(_ entry: (id: Int, name: String, vlan: Int, cancelled: Bool)) -> String {
        "{\"id\": \(entry.id), \"name\": \"\(entry.name)\", \"vlan\": \(entry.vlan), \"cancelled\": \(entry.cancelled)}"
    }

    /// Detail shape from `GET /vswitch/{id}`: a plain (unwrapped) object
    /// with populated `server`/`subnet`/`cloud_network` arrays.
    static func vSwitchDetailJSON(
        id: Int = 50301,
        name: String = "hrobot-test-vswitch",
        vlan: Int = 4001,
        cancelled: Bool = false,
        serverStatus: String = "ready"
    ) -> Data {
        Data("""
        {
            "id": \(id),
            "name": "\(name)",
            "vlan": \(vlan),
            "cancelled": \(cancelled),
            "server": [
                {
                    "server_number": 2321379,
                    "server_ip": "138.201.21.47",
                    "server_ipv6_net": "2a01:4f8:171:2c2c::",
                    "status": "\(serverStatus)"
                }
            ],
            "subnet": [
                {"ip": "10.0.0.0", "mask": "24"}
            ],
            "cloud_network": [
                {"id": 4711, "ip": "10.0.1.0", "mask": 24}
            ]
        }
        """.utf8)
    }

    static func failoverJSON(
        ip: String = "123.123.123.123",
        netmask: String = "255.255.255.255",
        serverIP: String = "78.46.1.93",
        serverNumber: Int = 321,
        activeServerIP: String? = "78.46.1.93"
    ) -> String {
        let activeValue = activeServerIP.map { "\"\($0)\"" } ?? "null"
        return """
        {
            "ip": "\(ip)",
            "netmask": "\(netmask)",
            "server_ip": "\(serverIP)",
            "server_ipv6_net": "2a01:4f8:d0a:2003::",
            "server_number": \(serverNumber),
            "active_server_ip": \(activeValue)
        }
        """
    }

    static func failoverEnvelopeJSON(ip: String = "123.123.123.123", activeServerIP: String? = "78.46.1.93") -> Data {
        Data("{\"failover\": \(failoverJSON(ip: ip, activeServerIP: activeServerIP))}".utf8)
    }

    static func failoverListJSON(ips: [String]) -> Data {
        let items = ips.map { "{\"failover\": \(failoverJSON(ip: $0))}" }.joined(separator: ",")
        return Data("[\(items)]".utf8)
    }
}

// MARK: - Model decoding

@Suite("RobotAPI vSwitch/Failover — model decoding")
struct RobotAPIVSwitchFailoverModelTests {
    private let decoder = JSONDecoder()

    @Test func vSwitchDecodesListShapeWithEmptyNestedArrays() throws {
        let data = VSwitchFailoverFixtures.vSwitchListJSON(entries: [(id: 1, name: "vs-a", vlan: 4000, cancelled: false)])
        let vswitches = try decoder.decode([RobotVSwitch].self, from: data)
        let vswitch = try #require(vswitches.first)
        #expect(vswitch.id == 1)
        #expect(vswitch.name == "vs-a")
        #expect(vswitch.vlan == 4000)
        #expect(vswitch.cancelled == false)
        #expect(vswitch.servers.isEmpty)
        #expect(vswitch.subnets.isEmpty)
        #expect(vswitch.cloudNetworks.isEmpty)
    }

    @Test func vSwitchListDecodesMultipleEntriesFromAPlainArray() throws {
        let data = VSwitchFailoverFixtures.vSwitchListJSON(entries: [
            (id: 1, name: "vs-a", vlan: 4000, cancelled: false),
            (id: 2, name: "vs-b", vlan: 4001, cancelled: true),
        ])
        let vswitches = try decoder.decode([RobotVSwitch].self, from: data)
        #expect(vswitches.map(\.id) == [1, 2])
        #expect(vswitches.map(\.cancelled) == [false, true])
    }

    @Test func vSwitchDecodesDetailShapeWithPopulatedNestedArrays() throws {
        let data = VSwitchFailoverFixtures.vSwitchDetailJSON()
        let vswitch = try decoder.decode(RobotVSwitch.self, from: data)
        #expect(vswitch.id == 50301)
        #expect(vswitch.vlan == 4001)

        let server = try #require(vswitch.servers.first)
        #expect(server.serverNumber == 2321379)
        #expect(server.serverIP == "138.201.21.47")
        #expect(server.status == .ready)

        let subnet = try #require(vswitch.subnets.first)
        #expect(subnet.ip == "10.0.0.0")
        #expect(subnet.mask == "24")

        let cloudNetwork = try #require(vswitch.cloudNetworks.first)
        #expect(cloudNetwork.id == 4711)
        #expect(cloudNetwork.mask == "24") // tolerates a bare JSON number, not just a string
    }

    @Test func vSwitchServerStatusDecodesReadyInProcessFailedAndUnknown() throws {
        for (raw, expected) in [
            ("ready", RobotVSwitchConnectionStatus.ready),
            ("in process", .inProcess),
            ("processing", .inProcess), // documented wire alias
            ("failed", .failed),
            ("something_new", .unknown),
        ] {
            let data = VSwitchFailoverFixtures.vSwitchDetailJSON(serverStatus: raw)
            let vswitch = try decoder.decode(RobotVSwitch.self, from: data)
            #expect(vswitch.servers.first?.status == expected, "raw value \"\(raw)\" should decode to \(expected)")
        }
    }

    @Test func vSwitchIsNotWrappedUnlikeOtherRobotResources() throws {
        // A plain vSwitch object at the top level (no {"vswitch": {...}}
        // envelope) must decode directly as RobotVSwitch.
        let plain = VSwitchFailoverFixtures.vSwitchDetailJSON()
        #expect(throws: Never.self) {
            _ = try decoder.decode(RobotVSwitch.self, from: plain)
        }
        // The wrapped shape every other Robot resource uses must NOT decode
        // as a plain RobotVSwitch (there's no top-level "id" key).
        let wrapped = Data("{\"vswitch\": \(String(data: plain, encoding: .utf8)!)}".utf8)
        #expect(throws: (any Error).self) {
            _ = try decoder.decode(RobotVSwitch.self, from: wrapped)
        }
    }

    @Test func failoverDecodesWrappedSingleObject() throws {
        let envelope = try decoder.decode(RobotFailoverEnvelope.self, from: VSwitchFailoverFixtures.failoverEnvelopeJSON())
        let failover = envelope.failover
        #expect(failover.ip == "123.123.123.123")
        #expect(failover.netmask == "255.255.255.255")
        #expect(failover.serverNumber == 321)
        #expect(failover.serverIP == "78.46.1.93")
        #expect(failover.activeServerIP == "78.46.1.93")
    }

    @Test func failoverToleratesNullActiveServerIP() throws {
        let data = VSwitchFailoverFixtures.failoverEnvelopeJSON(activeServerIP: nil)
        let envelope = try decoder.decode(RobotFailoverEnvelope.self, from: data)
        #expect(envelope.failover.activeServerIP == nil)
    }
}

/// Test-local wrapper mirroring `RobotDecoding`'s implicit envelope shape,
/// used to assert the wrapped JSON structure directly (the client itself
/// goes through `RobotDecoding.decodeWrapped`, exercised in the client
/// tests below).
private struct RobotFailoverEnvelope: Decodable {
    let failover: RobotFailover
}

// MARK: - Client behavior

@Suite("RobotAPI vSwitch/Failover — client")
struct RobotAPIVSwitchFailoverClientTests {
    private func makeClient(responses: [MockTransport.ScriptedResponse]) -> (RobotClient, MockTransport) {
        let transport = MockTransport(responses: responses)
        let client = RobotClient(username: "user", password: "pass", transport: transport)
        return (client, transport)
    }

    /// Decodes a form-urlencoded body into ordered (name, value) pairs.
    private func formPairs(_ request: URLRequest) throws -> [(String, String)] {
        let data = try #require(request.httpBody)
        let body = try #require(String(data: data, encoding: .utf8))
        return body.split(separator: "&").map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = String(parts[0]).removingPercentEncoding ?? String(parts[0])
            let value = parts.count > 1 ? (String(parts[1]).removingPercentEncoding ?? String(parts[1])) : ""
            return (name, value)
        }
    }

    // MARK: vSwitch

    @Test func listVSwitchesHitsPlainArrayEndpointAndDecodesListShape() async throws {
        let data = VSwitchFailoverFixtures.vSwitchListJSON(entries: [(id: 10, name: "vs-x", vlan: 4010, cancelled: false)])
        let (client, transport) = makeClient(responses: [.init(statusCode: 200, data: data)])

        let vswitches = try await client.listVSwitches()
        #expect(vswitches.map(\.id) == [10])
        #expect(vswitches[0].servers.isEmpty)

        let requests = await transport.recordedRequests
        #expect(requests.count == 1)
        #expect(requests[0].url?.absoluteString == "https://robot-ws.your-server.de/vswitch")
        #expect(requests[0].httpMethod == "GET")
    }

    @Test func vSwitchDetailHitsIDPathAndDecodesDetailShape() async throws {
        let (client, transport) = makeClient(responses: [.init(statusCode: 200, data: VSwitchFailoverFixtures.vSwitchDetailJSON(id: 777))])

        let vswitch = try await client.vSwitch(id: 777)
        #expect(vswitch.id == 777)
        #expect(vswitch.servers.count == 1)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://robot-ws.your-server.de/vswitch/777")
    }

    @Test func createVSwitchSendsNameAndVlanFormBodyAndDecodesResponse() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: VSwitchFailoverFixtures.vSwitchSingleListShapeJSON(id: 99, name: "new-vs", vlan: 4055)),
        ])

        let vswitch = try await client.createVSwitch(name: "new-vs", vlan: 4055)
        #expect(vswitch.id == 99)
        #expect(vswitch.vlan == 4055)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://robot-ws.your-server.de/vswitch")
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[0].value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")

        let pairs = try formPairs(requests[0])
        #expect(pairs.map(\.0) == ["name", "vlan"])
        #expect(pairs.map(\.1) == ["new-vs", "4055"])
    }

    @Test func updateVSwitchSendsNameAndVlanToIDPath() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: VSwitchFailoverFixtures.vSwitchSingleListShapeJSON(id: 99, name: "renamed", vlan: 4056)),
        ])

        let vswitch = try await client.updateVSwitch(id: 99, name: "renamed", vlan: 4056)
        #expect(vswitch.name == "renamed")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://robot-ws.your-server.de/vswitch/99")
        #expect(requests[0].httpMethod == "POST")

        let pairs = try formPairs(requests[0])
        #expect(pairs.map(\.0) == ["name", "vlan"])
        #expect(pairs.map(\.1) == ["renamed", "4056"])
    }

    @Test func deleteVSwitchDefaultsCancellationDateToNow() async throws {
        let (client, transport) = makeClient(responses: [.init(statusCode: 200, data: Data())])

        try await client.deleteVSwitch(id: 99)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://robot-ws.your-server.de/vswitch/99")
        #expect(requests[0].httpMethod == "DELETE")
        let pairs = try formPairs(requests[0])
        #expect(pairs.map(\.0) == ["cancellation_date"])
        #expect(pairs.map(\.1) == ["now"])
    }

    @Test func deleteVSwitchSendsExplicitCancellationDateWhenProvided() async throws {
        let (client, transport) = makeClient(responses: [.init(statusCode: 200, data: Data())])

        try await client.deleteVSwitch(id: 99, cancellationDate: "2026-08-01")

        let requests = await transport.recordedRequests
        let pairs = try formPairs(requests[0])
        #expect(pairs.map(\.0) == ["cancellation_date"])
        #expect(pairs.map(\.1) == ["2026-08-01"])
    }

    @Test func addVSwitchServersRepeatsServerFormKeyPerServerNumber() async throws {
        let (client, transport) = makeClient(responses: [.init(statusCode: 200, data: Data())])

        try await client.addVSwitchServers(id: 99, serverNumbers: [111, 222, 333])

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://robot-ws.your-server.de/vswitch/99/server")
        #expect(requests[0].httpMethod == "POST")
        let pairs = try formPairs(requests[0])
        #expect(pairs.map(\.0) == ["server[]", "server[]", "server[]"])
        #expect(pairs.map(\.1) == ["111", "222", "333"])
    }

    @Test func removeVSwitchServersRepeatsServerFormKeyPerServerNumber() async throws {
        let (client, transport) = makeClient(responses: [.init(statusCode: 200, data: Data())])

        try await client.removeVSwitchServers(id: 99, serverNumbers: [111])

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://robot-ws.your-server.de/vswitch/99/server")
        #expect(requests[0].httpMethod == "DELETE")
        let pairs = try formPairs(requests[0])
        #expect(pairs.map(\.0) == ["server[]"])
        #expect(pairs.map(\.1) == ["111"])
    }

    @Test func vSwitchGETsAreNeverCachedUnlikeServerIPSubnetKey() async throws {
        // Two consecutive listVSwitches() calls must both hit the network —
        // /vswitch is deliberately absent from RobotClient's 5-minute
        // cacheable-prefix allowlist (/server, /ip, /subnet, /key only).
        let page = VSwitchFailoverFixtures.vSwitchListJSON(entries: [(id: 1, name: "vs", vlan: 4000, cancelled: false)])
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: page),
            .init(statusCode: 200, data: page),
        ])

        _ = try await client.listVSwitches()
        _ = try await client.listVSwitches()

        let requests = await transport.recordedRequests
        #expect(requests.count == 2, "expected /vswitch to bypass the response cache on every call")
    }

    // MARK: Failover

    @Test func listFailoverIPsHitsWrappedListEndpoint() async throws {
        let data = VSwitchFailoverFixtures.failoverListJSON(ips: ["1.2.3.4", "5.6.7.8"])
        let (client, transport) = makeClient(responses: [.init(statusCode: 200, data: data)])

        let failovers = try await client.listFailoverIPs()
        #expect(failovers.map(\.ip) == ["1.2.3.4", "5.6.7.8"])

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://robot-ws.your-server.de/failover")
        #expect(requests[0].httpMethod == "GET")
    }

    @Test func failoverIPFetchesSingleByAddress() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: VSwitchFailoverFixtures.failoverEnvelopeJSON(ip: "9.9.9.9")),
        ])

        let failover = try await client.failoverIP(ip: "9.9.9.9")
        #expect(failover.ip == "9.9.9.9")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://robot-ws.your-server.de/failover/9.9.9.9")
    }

    @Test func switchFailoverSendsExactActiveServerIPFormBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: VSwitchFailoverFixtures.failoverEnvelopeJSON(ip: "1.2.3.4", activeServerIP: "10.0.0.5")),
        ])

        let failover = try await client.switchFailover(ip: "1.2.3.4", to: "10.0.0.5")
        #expect(failover.activeServerIP == "10.0.0.5")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://robot-ws.your-server.de/failover/1.2.3.4")
        #expect(requests[0].httpMethod == "POST")
        let pairs = try formPairs(requests[0])
        #expect(pairs.map(\.0) == ["active_server_ip"])
        #expect(pairs.map(\.1) == ["10.0.0.5"])
    }

    @Test func deleteFailoverRoutingHitsIPPathAndDecodesNullActiveServerIP() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: VSwitchFailoverFixtures.failoverEnvelopeJSON(ip: "1.2.3.4", activeServerIP: nil)),
        ])

        let failover = try await client.deleteFailoverRouting(ip: "1.2.3.4")
        #expect(failover.activeServerIP == nil)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://robot-ws.your-server.de/failover/1.2.3.4")
        #expect(requests[0].httpMethod == "DELETE")
    }

    @Test func failoverGETsAreNeverCached() async throws {
        let data = VSwitchFailoverFixtures.failoverListJSON(ips: ["1.1.1.1"])
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: data),
            .init(statusCode: 200, data: data),
        ])

        _ = try await client.listFailoverIPs()
        _ = try await client.listFailoverIPs()

        let requests = await transport.recordedRequests
        #expect(requests.count == 2, "expected /failover to bypass the response cache on every call")
    }

    // MARK: Error mapping

    @Test func switchFailoverAlreadyRoutedConflictSurfacesAsAPIError() async throws {
        let conflict = Data("""
        {"error": {"status": 409, "code": "FAILOVER_ALREADY_ROUTED", "message": "the failover IP is already routed to this server"}}
        """.utf8)
        let (client, _) = makeClient(responses: [.init(statusCode: 409, data: conflict)])

        do {
            _ = try await client.switchFailover(ip: "1.2.3.4", to: "10.0.0.5")
            Issue.record("Expected HetznerAPIError.api to be thrown")
        } catch HetznerAPIError.api(let code, let message) {
            #expect(code == "FAILOVER_ALREADY_ROUTED")
            #expect(message.contains("already routed"))
        }
    }

    @Test func vSwitchNotFoundSurfacesAsNotFound() async throws {
        let notFound = Data("""
        {"error": {"status": 404, "code": "VSWITCH_NOT_FOUND", "message": "vswitch not found"}}
        """.utf8)
        let (client, _) = makeClient(responses: [.init(statusCode: 404, data: notFound)])

        do {
            _ = try await client.vSwitch(id: 12345)
            Issue.record("Expected HetznerAPIError.notFound to be thrown")
        } catch HetznerAPIError.notFound {
            // expected
        }
    }
}
