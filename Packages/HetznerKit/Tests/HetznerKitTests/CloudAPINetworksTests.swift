import Foundation
import Testing
@testable import HetznerKit

/// Fixtures local to this file — shared `CloudAPIFixtures` is owned by
/// another worker and must not be modified.
private enum NetworkFixtures {
    static func networkJSON(id: Int = 200, name: String = "net1") -> String {
        """
        {
            "id": \(id),
            "name": "\(name)",
            "ip_range": "10.0.0.0/16",
            "subnets": [
                {"type": "cloud", "ip_range": "10.0.1.0/24", "network_zone": "eu-central", "gateway": "10.0.1.1", "vswitch_id": null}
            ],
            "routes": [
                {"destination": "10.100.1.0/24", "gateway": "10.0.1.1"}
            ],
            "servers": [42],
            "protection": {"delete": false},
            "labels": {"env": "prod"},
            "created": "2016-01-30T23:50:00+00:00",
            "expose_routes_to_vswitch": false
        }
        """
    }

    static func networkEnvelopeJSON(id: Int = 200, name: String = "net1") -> Data {
        Data("{\"network\": \(networkJSON(id: id, name: name))}".utf8)
    }

    static func networksPageJSON(networks: [(id: Int, name: String)], nextPage: Int?) -> Data {
        let items = networks.map { networkJSON(id: $0.id, name: $0.name) }.joined(separator: ",")
        let nextString = nextPage.map(String.init) ?? "null"
        let json = """
        {
            "networks": [\(items)],
            "meta": {
                "pagination": {
                    "page": 1, "per_page": 50, "previous_page": null,
                    "next_page": \(nextString), "last_page": 2, "total_entries": \(networks.count)
                }
            }
        }
        """
        return Data(json.utf8)
    }

    static func actionEnvelope(command: String) -> Data {
        Data(
            """
            {"action": {"id": 1, "command": "\(command)", "status": "running", "progress": 0, "started": "2016-01-30T23:50:00+00:00", "finished": null, "resources": [{"id": 200, "type": "network"}], "error": null}}
            """.utf8
        )
    }

    static func placementGroupJSON(id: Int = 300, name: String = "pg1") -> String {
        """
        {
            "id": \(id),
            "name": "\(name)",
            "labels": {"env": "prod"},
            "type": "spread",
            "servers": [42, 43],
            "created": "2016-01-30T23:50:00+00:00"
        }
        """
    }

    static func placementGroupEnvelopeJSON(id: Int = 300, name: String = "pg1") -> Data {
        Data("{\"placement_group\": \(placementGroupJSON(id: id, name: name))}".utf8)
    }

    static func placementGroupsPageJSON(groups: [(id: Int, name: String)], nextPage: Int?) -> Data {
        let items = groups.map { placementGroupJSON(id: $0.id, name: $0.name) }.joined(separator: ",")
        let nextString = nextPage.map(String.init) ?? "null"
        let json = """
        {
            "placement_groups": [\(items)],
            "meta": {
                "pagination": {
                    "page": 1, "per_page": 50, "previous_page": null,
                    "next_page": \(nextString), "last_page": 1, "total_entries": \(groups.count)
                }
            }
        }
        """
        return Data(json.utf8)
    }
}

@Suite("CloudClient+Networks")
struct CloudAPINetworksTests {
    private func makeClient(responses: [MockTransport.ScriptedResponse]) -> (CloudClient, MockTransport) {
        let transport = MockTransport(responses: responses)
        let client = CloudClient(token: "test-token", transport: transport)
        return (client, transport)
    }

    private func decodedBody(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    @Test func listNetworksWalksAllPages() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: NetworkFixtures.networksPageJSON(networks: [(1, "a"), (2, "b")], nextPage: 2)),
            .init(statusCode: 200, data: NetworkFixtures.networksPageJSON(networks: [(3, "c")], nextPage: nil)),
        ])

        let networks = try await client.listNetworks()

        #expect(networks.map(\.id) == [1, 2, 3])
        let requests = await transport.recordedRequests
        #expect(requests.count == 2)
        #expect(requests[0].httpMethod == "GET")
    }

    @Test func networkFetchesSingleByIDAndDecodesSubnetsAndRoutes() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: NetworkFixtures.networkEnvelopeJSON(id: 77, name: "solo")),
        ])
        let network = try await client.network(id: 77)
        #expect(network.id == 77)
        #expect(network.subnets.first?.type == .cloud)
        #expect(network.subnets.first?.networkZone == "eu-central")
        #expect(network.routes.first?.destination == "10.100.1.0/24")
        #expect(network.servers == [42])
        #expect(network.exposeRoutesToVswitch == false)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/networks/77")
    }

    @Test func createNetworkSendsSubnetsBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: NetworkFixtures.networkEnvelopeJSON()),
        ])

        let subnet = NetworkSubnetSpec(type: .cloud, ipRange: "10.0.1.0/24", networkZone: "eu-central")
        let network = try await client.createNetwork(name: "net1", ipRange: "10.0.0.0/16", subnets: [subnet], labels: ["env": "prod"])
        #expect(network.name == "net1")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/networks")
        #expect(requests[0].httpMethod == "POST")

        let body = try decodedBody(requests[0])
        #expect(body["name"] as? String == "net1")
        #expect(body["ip_range"] as? String == "10.0.0.0/16")
        let subnets = try #require(body["subnets"] as? [[String: Any]])
        #expect(subnets.count == 1)
        #expect(subnets[0]["type"] as? String == "cloud")
        #expect(subnets[0]["ip_range"] as? String == "10.0.1.0/24")
        #expect(subnets[0]["network_zone"] as? String == "eu-central")
    }

    @Test func deleteNetworkSendsDELETE() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 204, data: Data()),
        ])
        try await client.deleteNetwork(id: 200)
        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/networks/200")
        #expect(requests[0].httpMethod == "DELETE")
    }

    @Test func updateNetworkSendsPUTWithExposeRoutesFlag() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: NetworkFixtures.networkEnvelopeJSON(name: "renamed")),
        ])
        let network = try await client.updateNetwork(id: 200, name: "renamed", exposeRoutesToVswitch: true)
        #expect(network.name == "renamed")

        let requests = await transport.recordedRequests
        #expect(requests[0].httpMethod == "PUT")
        let body = try decodedBody(requests[0])
        #expect(body["name"] as? String == "renamed")
        #expect(body["expose_routes_to_vswitch"] as? Bool == true)
    }

    @Test func addSubnetSendsBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: NetworkFixtures.actionEnvelope(command: "add_subnet")),
        ])
        let action = try await client.addSubnet(networkID: 200, type: .cloud, ipRange: "10.0.2.0/24", networkZone: "eu-central")
        #expect(action.command == "add_subnet")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/networks/200/actions/add_subnet")
        let body = try decodedBody(requests[0])
        #expect(body["type"] as? String == "cloud")
        #expect(body["ip_range"] as? String == "10.0.2.0/24")
        #expect(body["network_zone"] as? String == "eu-central")
    }

    @Test func deleteSubnetSendsIPRangeBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: NetworkFixtures.actionEnvelope(command: "delete_subnet")),
        ])
        let action = try await client.deleteSubnet(networkID: 200, ipRange: "10.0.2.0/24")
        #expect(action.command == "delete_subnet")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/networks/200/actions/delete_subnet")
        let body = try decodedBody(requests[0])
        #expect(body["ip_range"] as? String == "10.0.2.0/24")
    }

    @Test func addRouteAndDeleteRouteSendDestinationAndGatewayBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: NetworkFixtures.actionEnvelope(command: "add_route")),
            .init(statusCode: 200, data: NetworkFixtures.actionEnvelope(command: "delete_route")),
        ])
        let addAction = try await client.addRoute(networkID: 200, destination: "10.100.1.0/24", gateway: "10.0.1.1")
        #expect(addAction.command == "add_route")
        let deleteAction = try await client.deleteRoute(networkID: 200, destination: "10.100.1.0/24", gateway: "10.0.1.1")
        #expect(deleteAction.command == "delete_route")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/networks/200/actions/add_route")
        #expect(requests[1].url?.absoluteString == "https://api.hetzner.cloud/v1/networks/200/actions/delete_route")
        let addBody = try decodedBody(requests[0])
        #expect(addBody["destination"] as? String == "10.100.1.0/24")
        #expect(addBody["gateway"] as? String == "10.0.1.1")
    }

    @Test func changeNetworkProtectionSendsDeleteBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: NetworkFixtures.actionEnvelope(command: "change_protection")),
        ])
        _ = try await client.changeNetworkProtection(id: 200, delete: true)
        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/networks/200/actions/change_protection")
        let body = try decodedBody(requests[0])
        #expect(body["delete"] as? Bool == true)
    }

    @Test func attachServerToNetworkSendsNetworkAndOptionalIP() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: NetworkFixtures.actionEnvelope(command: "attach_to_network")),
        ])
        let action = try await client.attachServerToNetwork(serverID: 42, networkID: 200, ip: "10.0.1.5")
        #expect(action.command == "attach_to_network")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/servers/42/actions/attach_to_network")
        let body = try decodedBody(requests[0])
        #expect(body["network"] as? Int == 200)
        #expect(body["ip"] as? String == "10.0.1.5")
    }

    @Test func attachServerToNetworkOmitsIPWhenNil() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: NetworkFixtures.actionEnvelope(command: "attach_to_network")),
        ])
        _ = try await client.attachServerToNetwork(serverID: 42, networkID: 200)

        let requests = await transport.recordedRequests
        let body = try decodedBody(requests[0])
        #expect(body["network"] as? Int == 200)
        #expect(body["ip"] == nil)
        #expect(body["alias_ips"] == nil)
    }

    @Test func detachServerFromNetworkSendsNetworkBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: NetworkFixtures.actionEnvelope(command: "detach_from_network")),
        ])
        let action = try await client.detachServerFromNetwork(serverID: 42, networkID: 200)
        #expect(action.command == "detach_from_network")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/servers/42/actions/detach_from_network")
        let body = try decodedBody(requests[0])
        #expect(body["network"] as? Int == 200)
    }
}

@Suite("CloudClient+PlacementGroups")
struct CloudAPIPlacementGroupsTests {
    private func makeClient(responses: [MockTransport.ScriptedResponse]) -> (CloudClient, MockTransport) {
        let transport = MockTransport(responses: responses)
        let client = CloudClient(token: "test-token", transport: transport)
        return (client, transport)
    }

    private func decodedBody(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    @Test func listPlacementGroupsWalksAllPages() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: NetworkFixtures.placementGroupsPageJSON(groups: [(1, "a")], nextPage: nil)),
        ])
        let groups = try await client.listPlacementGroups()
        #expect(groups.map(\.id) == [1])
        #expect(groups.first?.type == .spread)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString.contains("/placement_groups") == true)
    }

    @Test func placementGroupFetchesSingleByID() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: NetworkFixtures.placementGroupEnvelopeJSON(id: 9, name: "solo")),
        ])
        let group = try await client.placementGroup(id: 9)
        #expect(group.id == 9)
        #expect(group.name == "solo")
        #expect(group.servers == [42, 43])

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/placement_groups/9")
    }

    @Test func createPlacementGroupSendsTypeAndLabelsBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: NetworkFixtures.placementGroupEnvelopeJSON()),
        ])
        let group = try await client.createPlacementGroup(name: "pg1", type: .spread, labels: ["env": "prod"])
        #expect(group.name == "pg1")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/placement_groups")
        #expect(requests[0].httpMethod == "POST")
        let body = try decodedBody(requests[0])
        #expect(body["name"] as? String == "pg1")
        #expect(body["type"] as? String == "spread")
        #expect((body["labels"] as? [String: String])?["env"] == "prod")
    }

    @Test func deletePlacementGroupSendsDELETE() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 204, data: Data()),
        ])
        try await client.deletePlacementGroup(id: 300)
        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/placement_groups/300")
        #expect(requests[0].httpMethod == "DELETE")
    }
}
