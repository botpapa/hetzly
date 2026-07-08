import Foundation
import Testing
@testable import HetznerKit

@Suite("CloudClient")
struct CloudAPIClientTests {
    private func makeClient(responses: [MockTransport.ScriptedResponse]) -> (CloudClient, MockTransport) {
        let transport = MockTransport(responses: responses)
        let client = CloudClient(token: "test-token", transport: transport)
        return (client, transport)
    }

    @Test func listServersWalksAllPagesAndSortsByNameCaseInsensitively() async throws {
        let (client, transport) = makeClient(responses: [
            .init(
                statusCode: 200,
                data: CloudAPIFixtures.serversPageJSON(servers: [(1, "zeta"), (2, "Alpha")], nextPage: 2)
            ),
            .init(
                statusCode: 200,
                data: CloudAPIFixtures.serversPageJSON(servers: [(3, "beta")], nextPage: nil)
            ),
        ])

        let servers = try await client.listServers()

        #expect(servers.map(\.name) == ["Alpha", "beta", "zeta"])

        let requests = await transport.recordedRequests
        #expect(requests.count == 2)
        #expect(requests[0].url?.absoluteString.contains("/servers") == true)
        #expect(requests[0].url?.query?.contains("per_page=50") == true)
        #expect(requests[0].httpMethod == "GET")
    }

    @Test func serverFetchesSingleServerByID() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: CloudAPIFixtures.serverEnvelopeJSON(id: 99, name: "solo")),
        ])
        let server = try await client.server(id: 99)
        #expect(server.id == 99)
        #expect(server.name == "solo")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/servers/99")
        #expect(requests[0].httpMethod == "GET")
    }

    @Test func powerActionsHitTheExpectedPathAndMethod() async throws {
        let cases: [(String, String)] = [
            ("poweron", "poweron"),
            ("poweroff", "poweroff"),
            ("shutdown", "shutdown"),
            ("reboot", "reboot"),
            ("reset", "reset"),
        ]

        for (name, expectedSuffix) in cases {
            let (client, transport) = makeClient(responses: [
                .init(statusCode: 200, data: CloudAPIFixtures.actionEnvelopeJSON(command: name)),
            ])

            let action: Action
            switch name {
            case "poweron": action = try await client.powerOn(serverID: 5)
            case "poweroff": action = try await client.powerOff(serverID: 5)
            case "shutdown": action = try await client.shutdown(serverID: 5)
            case "reboot": action = try await client.reboot(serverID: 5)
            case "reset": action = try await client.reset(serverID: 5)
            default: fatalError("unreachable")
            }

            #expect(action.command == name)

            let requests = await transport.recordedRequests
            #expect(requests.count == 1)
            #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/servers/5/actions/\(expectedSuffix)")
            #expect(requests[0].httpMethod == "POST")
        }
    }

    @Test func deleteServerSendsDELETEAndDecodesActionEnvelope() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: CloudAPIFixtures.actionEnvelopeJSON(command: "delete_server")),
        ])

        let action = try await client.deleteServer(id: 5)
        #expect(action.command == "delete_server")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/servers/5")
        #expect(requests[0].httpMethod == "DELETE")
    }

    @Test func actionFetchesByID() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: CloudAPIFixtures.actionEnvelopeJSON(id: 123)),
        ])
        let action = try await client.action(id: 123)
        #expect(action.id == 123)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/actions/123")
    }

    @Test func serverMetricsBuildsCommaJoinedTypeAndISO8601Query() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: CloudAPIFixtures.metricsJSON),
        ])

        let start = Date(timeIntervalSince1970: 1_454_198_400)
        let end = Date(timeIntervalSince1970: 1_454_198_700)
        _ = try await client.serverMetrics(
            serverID: 1,
            types: [.cpu, .network],
            start: start,
            end: end,
            step: 60
        )

        let requests = await transport.recordedRequests
        let url = try #require(requests.first?.url)
        let query = try #require(url.query)
        #expect(query.contains("type=cpu,network"))
        #expect(query.contains("step=60"))
        #expect(url.path.contains("/servers/1/metrics"))
    }

    @Test func pricingDecodesFromRawEndpoint() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: CloudAPIFixtures.pricingJSON),
        ])
        let pricing = try await client.pricing()
        #expect(pricing.currency == "EUR")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/pricing")
    }

    @Test func validateTokenSucceedsOnGoodToken() async throws {
        let (client, _) = makeClient(responses: [
            .init(statusCode: 200, data: CloudAPIFixtures.pricingJSON),
        ])
        try await client.validateToken()
    }

    @Test func validateTokenThrowsUnauthorizedOn401() async throws {
        let (client, _) = makeClient(responses: [
            .init(statusCode: 401, data: Data()),
        ])
        do {
            try await client.validateToken()
            Issue.record("Expected validateToken to throw")
        } catch HetznerAPIError.unauthorized {
            // expected
        }
    }
}
