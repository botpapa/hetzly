import Foundation
import Testing
@testable import HetznerKit

/// Fixtures local to this suite — kept separate from the shared
/// `CloudAPIFixtures` enum (owned by another worker) to avoid cross-file
/// edits outside this worker's scope.
private enum IPFixtures {
    static let datacenterJSON = """
    {
        "id": 1,
        "name": "fsn1-dc14",
        "description": "Falkenstein 1 DC14",
        "location": {
            "id": 1,
            "name": "fsn1",
            "description": "Falkenstein DC Park 1",
            "country": "DE",
            "city": "Falkenstein",
            "latitude": 50.47612,
            "longitude": 12.370071,
            "network_zone": "eu-central"
        }
    }
    """

    static let locationJSON = """
    {
        "id": 1,
        "name": "fsn1",
        "description": "Falkenstein DC Park 1",
        "country": "DE",
        "city": "Falkenstein",
        "latitude": 50.47612,
        "longitude": 12.370071,
        "network_zone": "eu-central"
    }
    """

    static func primaryIPJSON(id: Int = 1, name: String = "primary-1", type: String = "ipv4", assigneeID: Int? = 42) -> String {
        let assigneeValue = assigneeID.map(String.init) ?? "null"
        return """
        {
            "id": \(id),
            "name": "\(name)",
            "ip": "1.2.3.4",
            "type": "\(type)",
            "assignee_id": \(assigneeValue),
            "assignee_type": "server",
            "auto_delete": true,
            "blocked": false,
            "created": "2016-01-30T23:50:00+00:00",
            "datacenter": \(datacenterJSON),
            "dns_ptr": [{"ip": "1.2.3.4", "dns_ptr": "server.example.com"}],
            "labels": {"env": "prod"},
            "protection": {"delete": false}
        }
        """
    }

    static func primaryIPEnvelopeJSON(id: Int = 1, name: String = "primary-1") -> Data {
        Data("{\"primary_ip\": \(primaryIPJSON(id: id, name: name))}".utf8)
    }

    static func primaryIPsPageJSON(ips: [(id: Int, name: String)], nextPage: Int?) -> Data {
        let items = ips.map { primaryIPJSON(id: $0.id, name: $0.name) }.joined(separator: ",")
        let nextString = nextPage.map(String.init) ?? "null"
        let json = """
        {
            "primary_ips": [\(items)],
            "meta": {
                "pagination": {
                    "page": 1, "per_page": 50, "previous_page": null,
                    "next_page": \(nextString), "last_page": 2, "total_entries": \(ips.count)
                }
            }
        }
        """
        return Data(json.utf8)
    }

    static func createPrimaryIPEnvelopeJSON(id: Int = 5, name: String = "new-ip", includeAction: Bool) -> Data {
        let actionValue = includeAction ? actionJSON(id: 100, command: "assign_primary_ip") : "null"
        let json = """
        {
            "primary_ip": \(primaryIPJSON(id: id, name: name)),
            "action": \(actionValue)
        }
        """
        return Data(json.utf8)
    }

    static func floatingIPJSON(id: Int = 1, name: String = "floating-1", server: Int? = 99, description: String? = "spare") -> String {
        let serverValue = server.map(String.init) ?? "null"
        let descriptionValue = description.map { "\"\($0)\"" } ?? "null"
        return """
        {
            "id": \(id),
            "name": "\(name)",
            "description": \(descriptionValue),
            "ip": "5.6.7.8",
            "type": "ipv4",
            "server": \(serverValue),
            "dns_ptr": [{"ip": "5.6.7.8", "dns_ptr": null}],
            "home_location": \(locationJSON),
            "blocked": false,
            "protection": {"delete": true},
            "labels": {},
            "created": "2016-01-30T23:50:00+00:00"
        }
        """
    }

    static func floatingIPEnvelopeJSON(id: Int = 1, name: String = "floating-1") -> Data {
        Data("{\"floating_ip\": \(floatingIPJSON(id: id, name: name))}".utf8)
    }

    static func floatingIPsPageJSON(ips: [(id: Int, name: String)], nextPage: Int?) -> Data {
        let items = ips.map { floatingIPJSON(id: $0.id, name: $0.name) }.joined(separator: ",")
        let nextString = nextPage.map(String.init) ?? "null"
        let json = """
        {
            "floating_ips": [\(items)],
            "meta": {
                "pagination": {
                    "page": 1, "per_page": 50, "previous_page": null,
                    "next_page": \(nextString), "last_page": 2, "total_entries": \(ips.count)
                }
            }
        }
        """
        return Data(json.utf8)
    }

    static func createFloatingIPEnvelopeJSON(id: Int = 5, name: String = "new-floating", includeAction: Bool) -> Data {
        let actionValue = includeAction ? actionJSON(id: 200, command: "assign_floating_ip") : "null"
        let json = """
        {
            "floating_ip": \(floatingIPJSON(id: id, name: name)),
            "action": \(actionValue)
        }
        """
        return Data(json.utf8)
    }

    static func actionEnvelopeJSON(id: Int, command: String) -> Data {
        Data("{\"action\": \(actionJSON(id: id, command: command))}".utf8)
    }

    static func actionJSON(id: Int, command: String) -> String {
        """
        {
            "id": \(id),
            "command": "\(command)",
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

@Suite("CloudClient+PrimaryIPs and CloudClient+FloatingIPs")
struct CloudAPIIPsTests {
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

    // MARK: - PrimaryIP decoding

    @Test func decodesPrimaryIPFull() throws {
        let envelope = try decoder.decode(PrimaryIPEnvelope.self, from: IPFixtures.primaryIPEnvelopeJSON())
        let ip = envelope.primaryIP

        #expect(ip.id == 1)
        #expect(ip.type == .ipv4)
        #expect(ip.assigneeID == 42)
        #expect(ip.autoDelete == true)
        #expect(ip.datacenter.location.city == "Falkenstein")
        #expect(ip.dnsPtr.first?.dnsPtr == "server.example.com")
        #expect(ip.protection.delete == false)
    }

    @Test func unknownPrimaryIPTypeDecodesToUnknownInsteadOfThrowing() throws {
        let json = Data(IPFixtures.primaryIPJSON(type: "ipv9").utf8)
        let ip = try decoder.decode(PrimaryIP.self, from: json)
        #expect(ip.type == .unknown)
    }

    // MARK: - PrimaryIP client

    @Test func listPrimaryIPsWalksAllPages() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: IPFixtures.primaryIPsPageJSON(ips: [(1, "a"), (2, "b")], nextPage: 2)),
            .init(statusCode: 200, data: IPFixtures.primaryIPsPageJSON(ips: [(3, "c")], nextPage: nil)),
        ])
        let ips = try await client.listPrimaryIPs()
        #expect(ips.count == 3)

        let requests = await transport.recordedRequests
        #expect(requests.count == 2)
    }

    @Test func primaryIPFetchesByID() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: IPFixtures.primaryIPEnvelopeJSON(id: 9, name: "solo-ip")),
        ])
        let ip = try await client.primaryIP(id: 9)
        #expect(ip.id == 9)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/primary_ips/9")
    }

    @Test func createPrimaryIPWithAssigneeIDReturnsAction() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: IPFixtures.createPrimaryIPEnvelopeJSON(id: 5, name: "new-ip", includeAction: true)),
        ])
        let created = try await client.createPrimaryIP(name: "new-ip", type: .ipv4, assigneeID: 42, autoDelete: true)
        #expect(created.primaryIP.id == 5)
        #expect(created.action?.id == 100)

        let requests = await transport.recordedRequests
        let object = try jsonObject(from: requests[0].httpBody)
        #expect(object["type"] as? String == "ipv4")
        #expect(object["assignee_id"] as? Int == 42)
        #expect(object["auto_delete"] as? Bool == true)
        #expect(object["datacenter"] == nil)
    }

    @Test func createPrimaryIPWithDatacenterOmitsAssigneeAndActionIsNil() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: IPFixtures.createPrimaryIPEnvelopeJSON(includeAction: false)),
        ])
        let created = try await client.createPrimaryIP(name: "standalone", type: .ipv6, datacenterName: "fsn1-dc14")
        #expect(created.action == nil)

        let requests = await transport.recordedRequests
        let object = try jsonObject(from: requests[0].httpBody)
        #expect(object["datacenter"] as? String == "fsn1-dc14")
        #expect(object["assignee_id"] == nil)
    }

    @Test func deletePrimaryIPSendsDELETE() async throws {
        let (client, transport) = makeClient(responses: [.init(statusCode: 204, data: Data())])
        try await client.deletePrimaryIP(id: 5)

        let requests = await transport.recordedRequests
        #expect(requests[0].httpMethod == "DELETE")
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/primary_ips/5")
    }

    @Test func updatePrimaryIPOmitsUnsetFields() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: IPFixtures.primaryIPEnvelopeJSON(id: 5, name: "renamed")),
        ])
        _ = try await client.updatePrimaryIP(id: 5, name: "renamed")

        let requests = await transport.recordedRequests
        let object = try jsonObject(from: requests[0].httpBody)
        #expect(object["name"] as? String == "renamed")
        #expect(object["auto_delete"] == nil)
        #expect(object["labels"] == nil)
    }

    @Test func assignPrimaryIPSendsAssigneeIDAndTypeServer() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: IPFixtures.actionEnvelopeJSON(id: 10, command: "assign_primary_ip")),
        ])
        let action = try await client.assignPrimaryIP(id: 5, assigneeID: 42)
        #expect(action.id == 10)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/primary_ips/5/actions/assign")
        let object = try jsonObject(from: requests[0].httpBody)
        #expect(object["assignee_id"] as? Int == 42)
        #expect(object["type"] as? String == "server")
    }

    @Test func unassignPrimaryIPSendsNoBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: IPFixtures.actionEnvelopeJSON(id: 11, command: "unassign_primary_ip")),
        ])
        _ = try await client.unassignPrimaryIP(id: 5)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/primary_ips/5/actions/unassign")
        #expect(requests[0].httpBody == nil)
    }

    @Test func changePrimaryIPProtectionSendsDeleteFlag() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: IPFixtures.actionEnvelopeJSON(id: 12, command: "change_protection")),
        ])
        _ = try await client.changePrimaryIPProtection(id: 5, delete: true)

        let requests = await transport.recordedRequests
        let object = try jsonObject(from: requests[0].httpBody)
        #expect(object["delete"] as? Bool == true)
    }

    @Test func setPrimaryIPRDNSIncludesExplicitNullWhenResetting() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: IPFixtures.actionEnvelopeJSON(id: 13, command: "change_dns_ptr")),
        ])
        _ = try await client.setPrimaryIPRDNS(id: 5, ip: "1.2.3.4", dnsPtr: nil)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/primary_ips/5/actions/change_dns_ptr")
        let data = try #require(requests[0].httpBody)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["ip"] as? String == "1.2.3.4")
        // The key must be present (encoding `null`), not omitted — omission
        // would leave the existing PTR untouched instead of resetting it.
        #expect(object?.keys.contains("dns_ptr") == true)
        #expect(object?["dns_ptr"] is NSNull)
    }

    // MARK: - FloatingIP decoding

    @Test func decodesFloatingIPFull() throws {
        let envelope = try decoder.decode(FloatingIPEnvelope.self, from: IPFixtures.floatingIPEnvelopeJSON())
        let ip = envelope.floatingIP

        #expect(ip.id == 1)
        #expect(ip.server == 99)
        #expect(ip.description == "spare")
        #expect(ip.homeLocation.name == "fsn1")
        #expect(ip.protection.delete == true)
        #expect(ip.dnsPtr.first?.dnsPtr == nil)
    }

    @Test func unassignedFloatingIPHasNilServer() throws {
        let json = Data(IPFixtures.floatingIPJSON(server: nil, description: nil).utf8)
        let ip = try decoder.decode(FloatingIP.self, from: json)
        #expect(ip.server == nil)
        #expect(ip.description == nil)
    }

    // MARK: - FloatingIP client

    @Test func listFloatingIPsWalksAllPages() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: IPFixtures.floatingIPsPageJSON(ips: [(1, "a"), (2, "b")], nextPage: 2)),
            .init(statusCode: 200, data: IPFixtures.floatingIPsPageJSON(ips: [(3, "c")], nextPage: nil)),
        ])
        let ips = try await client.listFloatingIPs()
        #expect(ips.count == 3)

        let requests = await transport.recordedRequests
        #expect(requests.count == 2)
    }

    @Test func floatingIPFetchesByID() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: IPFixtures.floatingIPEnvelopeJSON(id: 9, name: "solo-floating")),
        ])
        let ip = try await client.floatingIP(id: 9)
        #expect(ip.id == 9)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/floating_ips/9")
    }

    @Test func createFloatingIPWithServerIDReturnsAction() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: IPFixtures.createFloatingIPEnvelopeJSON(id: 5, name: "new-floating", includeAction: true)),
        ])
        let created = try await client.createFloatingIP(name: "new-floating", type: .ipv4, serverID: 99, description: "backup")
        #expect(created.floatingIP.id == 5)
        #expect(created.action?.id == 200)

        let requests = await transport.recordedRequests
        let object = try jsonObject(from: requests[0].httpBody)
        #expect(object["server"] as? Int == 99)
        #expect(object["description"] as? String == "backup")
        #expect(object["home_location"] == nil)
    }

    @Test func deleteFloatingIPSendsDELETE() async throws {
        let (client, transport) = makeClient(responses: [.init(statusCode: 204, data: Data())])
        try await client.deleteFloatingIP(id: 5)

        let requests = await transport.recordedRequests
        #expect(requests[0].httpMethod == "DELETE")
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/floating_ips/5")
    }

    @Test func assignFloatingIPSendsServerID() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: IPFixtures.actionEnvelopeJSON(id: 20, command: "assign_floating_ip")),
        ])
        let action = try await client.assignFloatingIP(id: 5, serverID: 99)
        #expect(action.id == 20)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/floating_ips/5/actions/assign")
        let object = try jsonObject(from: requests[0].httpBody)
        #expect(object["server"] as? Int == 99)
    }

    @Test func unassignFloatingIPSendsNoBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: IPFixtures.actionEnvelopeJSON(id: 21, command: "unassign_floating_ip")),
        ])
        _ = try await client.unassignFloatingIP(id: 5)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/floating_ips/5/actions/unassign")
        #expect(requests[0].httpBody == nil)
    }

    @Test func changeFloatingIPProtectionSendsDeleteFlag() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: IPFixtures.actionEnvelopeJSON(id: 22, command: "change_protection")),
        ])
        _ = try await client.changeFloatingIPProtection(id: 5, delete: false)

        let requests = await transport.recordedRequests
        let object = try jsonObject(from: requests[0].httpBody)
        #expect(object["delete"] as? Bool == false)
    }

    @Test func setFloatingIPRDNSSendsIPAndDNSPtr() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: IPFixtures.actionEnvelopeJSON(id: 23, command: "change_dns_ptr")),
        ])
        _ = try await client.setFloatingIPRDNS(id: 5, ip: "5.6.7.8", dnsPtr: "host.example.com")

        let requests = await transport.recordedRequests
        let object = try jsonObject(from: requests[0].httpBody)
        #expect(object["ip"] as? String == "5.6.7.8")
        #expect(object["dns_ptr"] as? String == "host.example.com")
    }
}
