import Foundation
import Testing
@testable import HetznerKit

/// Fixtures local to this suite — kept separate from the shared
/// `CloudAPIFixtures` enum (owned by another worker) to avoid cross-file
/// edits outside this worker's scope.
private enum FirewallFixtures {
    static func ruleJSON(
        direction: String = "in",
        proto: String = "tcp",
        port: String? = "80",
        sourceIPs: [String] = ["0.0.0.0/0", "::/0"],
        destinationIPs: [String] = [],
        description: String? = "allow http"
    ) -> String {
        let portValue = port.map { "\"\($0)\"" } ?? "null"
        let descriptionValue = description.map { "\"\($0)\"" } ?? "null"
        let sources = sourceIPs.map { "\"\($0)\"" }.joined(separator: ",")
        let destinations = destinationIPs.map { "\"\($0)\"" }.joined(separator: ",")
        return """
        {
            "direction": "\(direction)",
            "protocol": "\(proto)",
            "port": \(portValue),
            "source_ips": [\(sources)],
            "destination_ips": [\(destinations)],
            "description": \(descriptionValue)
        }
        """
    }

    static func firewallJSON(id: Int = 1, name: String = "web-fw", rules: [String] = [ruleJSON()]) -> String {
        """
        {
            "id": \(id),
            "name": "\(name)",
            "labels": {"env": "prod"},
            "created": "2016-01-30T23:50:00+00:00",
            "rules": [\(rules.joined(separator: ","))],
            "applied_to": [
                {"type": "server", "server": {"id": 42}, "label_selector": null, "applied_to_resources": null},
                {
                    "type": "label_selector",
                    "server": null,
                    "label_selector": {"selector": "env=prod"},
                    "applied_to_resources": [{"type": "server", "server": {"id": 43}}]
                }
            ]
        }
        """
    }

    static func firewallEnvelopeJSON(id: Int = 1, name: String = "web-fw") -> Data {
        Data("{\"firewall\": \(firewallJSON(id: id, name: name))}".utf8)
    }

    static func firewallsPageJSON(firewalls: [(id: Int, name: String)], nextPage: Int?) -> Data {
        let items = firewalls.map { firewallJSON(id: $0.id, name: $0.name) }.joined(separator: ",")
        let nextString = nextPage.map(String.init) ?? "null"
        let json = """
        {
            "firewalls": [\(items)],
            "meta": {
                "pagination": {
                    "page": 1, "per_page": 50, "previous_page": null,
                    "next_page": \(nextString), "last_page": 2, "total_entries": \(firewalls.count)
                }
            }
        }
        """
        return Data(json.utf8)
    }

    static func createFirewallEnvelopeJSON(id: Int = 5, name: String = "new-fw") -> Data {
        let json = """
        {
            "firewall": \(firewallJSON(id: id, name: name, rules: [])),
            "actions": [\(actionJSON(id: 100)), \(actionJSON(id: 101))]
        }
        """
        return Data(json.utf8)
    }

    static func actionsEnvelopeJSON(ids: [Int]) -> Data {
        let items = ids.map { actionJSON(id: $0) }.joined(separator: ",")
        return Data("{\"actions\": [\(items)]}".utf8)
    }

    static func actionJSON(id: Int) -> String {
        """
        {
            "id": \(id),
            "command": "apply_firewall",
            "status": "running",
            "progress": 0,
            "started": "2016-01-30T23:50:00+00:00",
            "finished": null,
            "resources": [{"id": 42, "type": "server"}],
            "error": null
        }
        """
    }
}

@Suite("CloudClient+Firewalls")
struct CloudAPIFirewallsTests {
    private let decoder = makeHetznerJSONDecoder()

    private func makeClient(responses: [MockTransport.ScriptedResponse]) -> (CloudClient, MockTransport) {
        let transport = MockTransport(responses: responses)
        let client = CloudClient(token: "test-token", transport: transport)
        return (client, transport)
    }

    private func jsonObject(from data: Data?) throws -> [String: Any] {
        let data = try #require(data)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    // MARK: - Model decoding

    @Test func decodesFirewallWithRulesAndAppliedTo() throws {
        let envelope = try decoder.decode(FirewallEnvelope.self, from: FirewallFixtures.firewallEnvelopeJSON())
        let firewall = envelope.firewall

        #expect(firewall.id == 1)
        #expect(firewall.name == "web-fw")
        #expect(firewall.labels == ["env": "prod"])
        #expect(firewall.rules.count == 1)
        #expect(firewall.rules[0].direction == .inbound)
        #expect(firewall.rules[0].networkProtocol == .tcp)
        #expect(firewall.rules[0].port == "80")
        #expect(firewall.appliedTo.count == 2)
        #expect(firewall.appliedTo[0].type == .server)
        #expect(firewall.appliedTo[0].server?.id == 42)
        #expect(firewall.appliedTo[1].type == .labelSelector)
        #expect(firewall.appliedTo[1].labelSelector?.selector == "env=prod")
        #expect(firewall.appliedTo[1].appliedToResources?.first?.server?.id == 43)
    }

    @Test func unknownDirectionAndProtocolDecodeToUnknownInsteadOfThrowing() throws {
        let json = Data(FirewallFixtures.ruleJSON(direction: "sideways", proto: "quic", port: nil).utf8)
        let rule = try decoder.decode(FirewallRule.self, from: json)
        #expect(rule.direction == .unknown)
        #expect(rule.networkProtocol == .unknown)
        #expect(rule.port == nil)
    }

    @Test func unknownFirewallResourceTypeDecodesToUnknown() throws {
        let json = Data(#"{"type": "future_thing", "server": null, "label_selector": null, "applied_to_resources": null}"#.utf8)
        let resource = try decoder.decode(FirewallResource.self, from: json)
        #expect(resource.type == .unknown)
    }

    // MARK: - Rule round-trip (icmp has no port; both directions)

    @Test func ruleRoundTripsWithNilPortForICMP() throws {
        let rule = FirewallRule(
            direction: .inbound,
            networkProtocol: .icmp,
            port: nil,
            sourceIPs: ["0.0.0.0/0"],
            destinationIPs: [],
            description: "allow ping"
        )
        let data = try JSONEncoder().encode(rule)
        let decoded = try decoder.decode(FirewallRule.self, from: data)
        #expect(decoded == rule)
        #expect(decoded.port == nil)

        let object = try jsonObject(from: data)
        #expect(object["protocol"] as? String == "icmp")
        // Default `Codable` synthesis encodes optional stored properties with
        // `encodeIfPresent`, so a nil port is omitted entirely rather than
        // sent as an explicit `null`.
        #expect(object["port"] == nil)
    }

    @Test func ruleRoundTripsForBothDirectionsWithPortRange() throws {
        for (direction, wireValue) in [(FirewallDirection.inbound, "in"), (.outbound, "out")] {
            let rule = FirewallRule(
                direction: direction,
                networkProtocol: .tcp,
                port: "80-85",
                sourceIPs: ["10.0.0.0/8"],
                destinationIPs: ["10.0.0.1"],
                description: nil
            )
            let data = try JSONEncoder().encode(rule)
            let decoded = try decoder.decode(FirewallRule.self, from: data)
            #expect(decoded == rule)

            let object = try jsonObject(from: data)
            #expect(object["direction"] as? String == wireValue)
            #expect(object["port"] as? String == "80-85")
        }
    }

    // MARK: - CloudClient

    @Test func listFirewallsWalksAllPages() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: FirewallFixtures.firewallsPageJSON(firewalls: [(1, "a"), (2, "b")], nextPage: 2)),
            .init(statusCode: 200, data: FirewallFixtures.firewallsPageJSON(firewalls: [(3, "c")], nextPage: nil)),
        ])

        let firewalls = try await client.listFirewalls()
        #expect(firewalls.count == 3)

        let requests = await transport.recordedRequests
        #expect(requests.count == 2)
        #expect(requests[0].url?.absoluteString.contains("/firewalls") == true)
    }

    @Test func firewallFetchesByID() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: FirewallFixtures.firewallEnvelopeJSON(id: 9, name: "solo-fw")),
        ])
        let firewall = try await client.firewall(id: 9)
        #expect(firewall.id == 9)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/firewalls/9")
        #expect(requests[0].httpMethod == "GET")
    }

    @Test func createFirewallSendsApplyToAndRulesAndDecodesPluralActions() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: FirewallFixtures.createFirewallEnvelopeJSON(id: 5, name: "new-fw")),
        ])

        let rule = FirewallRule(
            direction: .inbound,
            networkProtocol: .tcp,
            port: "22",
            sourceIPs: ["0.0.0.0/0"],
            destinationIPs: [],
            description: "ssh"
        )
        let created = try await client.createFirewall(
            name: "new-fw",
            rules: [rule],
            applyTo: [.server(id: 42), .labelSelector("env=prod")],
            labels: ["team": "infra"]
        )

        #expect(created.firewall.id == 5)
        #expect(created.actions.count == 2)

        let requests = await transport.recordedRequests
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/firewalls")

        let object = try jsonObject(from: requests[0].httpBody)
        #expect(object["name"] as? String == "new-fw")
        #expect((object["labels"] as? [String: String])?["team"] == "infra")

        let rules = try #require(object["rules"] as? [[String: Any]])
        #expect(rules.count == 1)
        #expect(rules[0]["protocol"] as? String == "tcp")

        let applyTo = try #require(object["apply_to"] as? [[String: Any]])
        #expect(applyTo.count == 2)
        #expect(applyTo[0]["type"] as? String == "server")
        #expect((applyTo[0]["server"] as? [String: Any])?["id"] as? Int == 42)
        #expect(applyTo[1]["type"] as? String == "label_selector")
        #expect((applyTo[1]["label_selector"] as? [String: Any])?["selector"] as? String == "env=prod")
    }

    @Test func createFirewallWithoutApplyToOmitsTheKey() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: FirewallFixtures.createFirewallEnvelopeJSON()),
        ])
        _ = try await client.createFirewall(name: "bare-fw", rules: [])

        let requests = await transport.recordedRequests
        let object = try jsonObject(from: requests[0].httpBody)
        #expect(object["apply_to"] == nil)
        #expect(object["labels"] == nil)
    }

    @Test func deleteFirewallSendsDELETEAndExpectsNoContent() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 204, data: Data()),
        ])
        try await client.deleteFirewall(id: 5)

        let requests = await transport.recordedRequests
        #expect(requests[0].httpMethod == "DELETE")
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/firewalls/5")
    }

    @Test func updateFirewallSendsPUTWithOnlyProvidedFields() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: FirewallFixtures.firewallEnvelopeJSON(id: 5, name: "renamed")),
        ])
        let firewall = try await client.updateFirewall(id: 5, name: "renamed")
        #expect(firewall.name == "renamed")

        let requests = await transport.recordedRequests
        #expect(requests[0].httpMethod == "PUT")
        let object = try jsonObject(from: requests[0].httpBody)
        #expect(object["name"] as? String == "renamed")
        #expect(object["labels"] == nil)
    }

    @Test func setFirewallRulesUsesPluralActionsEnvelope() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: FirewallFixtures.actionsEnvelopeJSON(ids: [10, 11, 12])),
        ])
        let rule = FirewallRule(
            direction: .outbound,
            networkProtocol: .udp,
            port: "53",
            sourceIPs: [],
            destinationIPs: ["0.0.0.0/0"],
            description: nil
        )
        let actions = try await client.setFirewallRules(id: 5, rules: [rule])
        #expect(actions.map(\.id) == [10, 11, 12])

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/firewalls/5/actions/set_rules")
        let object = try jsonObject(from: requests[0].httpBody)
        let rules = try #require(object["rules"] as? [[String: Any]])
        #expect(rules[0]["protocol"] as? String == "udp")
    }

    @Test func applyFirewallBuildsServerAndLabelSelectorTargets() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: FirewallFixtures.actionsEnvelopeJSON(ids: [20])),
        ])
        let actions = try await client.applyFirewall(id: 5, toServerIDs: [1, 2], labelSelectors: ["role=web"])
        #expect(actions.count == 1)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/firewalls/5/actions/apply_to_resources")
        let object = try jsonObject(from: requests[0].httpBody)
        let applyTo = try #require(object["apply_to"] as? [[String: Any]])
        #expect(applyTo.count == 3)
        #expect(applyTo[0]["type"] as? String == "server")
        #expect((applyTo[0]["server"] as? [String: Any])?["id"] as? Int == 1)
        #expect(applyTo[2]["type"] as? String == "label_selector")
        #expect((applyTo[2]["label_selector"] as? [String: Any])?["selector"] as? String == "role=web")
    }

    @Test func removeFirewallSendsRemoveFromKey() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: FirewallFixtures.actionsEnvelopeJSON(ids: [30])),
        ])
        _ = try await client.removeFirewall(id: 5, fromServerIDs: [7], labelSelectors: [])

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/firewalls/5/actions/remove_from_resources")
        let object = try jsonObject(from: requests[0].httpBody)
        let removeFrom = try #require(object["remove_from"] as? [[String: Any]])
        #expect(removeFrom.count == 1)
        #expect((removeFrom[0]["server"] as? [String: Any])?["id"] as? Int == 7)
    }
}
