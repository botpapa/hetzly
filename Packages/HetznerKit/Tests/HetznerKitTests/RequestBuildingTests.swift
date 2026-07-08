import Foundation
import Testing
@testable import HetznerKit

private struct Dummy: Decodable, Sendable, Equatable {
    let id: Int
}

@Suite("Request building")
struct RequestBuildingTests {
    private func makeClient(
        auth: AuthMethod,
        responses: [MockTransport.ScriptedResponse]
    ) -> (HetznerHTTPClient, MockTransport) {
        let transport = MockTransport(responses: responses)
        let configuration = APIConfiguration(
            baseURL: URL(string: "https://api.hetzner.cloud/v1")!,
            auth: auth
        )
        let client = HetznerHTTPClient(
            configuration: configuration,
            transport: transport,
            rateLimiter: RateLimiter(budget: 1000, window: 60)
        )
        return (client, transport)
    }

    @Test func bearerAuthorizationHeader() async throws {
        let (client, transport) = makeClient(
            auth: .bearer(token: "secret-token"),
            responses: [.init(statusCode: 200, data: Data(#"{"id":1}"#.utf8))]
        )
        let _: Dummy = try await client.send(Endpoint(path: "/servers"))

        let requests = await transport.recordedRequests
        #expect(requests.count == 1)
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/servers")
        #expect(requests[0].httpMethod == "GET")
    }

    @Test func basicAuthorizationHeader() async throws {
        let (client, transport) = makeClient(
            auth: .basic(username: "user", password: "pass"),
            responses: [.init(statusCode: 200, data: Data(#"{"id":1}"#.utf8))]
        )
        let _: Dummy = try await client.send(Endpoint(path: "/servers"))

        let expected = "Basic " + Data("user:pass".utf8).base64EncodedString()
        let requests = await transport.recordedRequests
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == expected)
    }

    @Test func encodesQueryItems() async throws {
        let (client, transport) = makeClient(
            auth: .bearer(token: "t"),
            responses: [.init(statusCode: 200, data: Data(#"{"id":1}"#.utf8))]
        )
        let endpoint = Endpoint(
            path: "/servers",
            query: [URLQueryItem(name: "page", value: "2"), URLQueryItem(name: "per_page", value: "10")]
        )
        let _: Dummy = try await client.send(endpoint)

        let requests = await transport.recordedRequests
        let query = requests[0].url?.query ?? ""
        #expect(query.contains("page=2"))
        #expect(query.contains("per_page=10"))
    }

    @Test func jsonContentTypeWhenBodyPresent() async throws {
        let (client, transport) = makeClient(
            auth: .bearer(token: "t"),
            responses: [.init(statusCode: 201, data: Data(#"{"id":1}"#.utf8))]
        )
        let body = Data(#"{"name":"srv"}"#.utf8)
        let endpoint = Endpoint(method: .post, path: "/servers", body: body)
        let _: Dummy = try await client.send(endpoint)

        let requests = await transport.recordedRequests
        #expect(requests[0].value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(requests[0].httpBody == body)
        #expect(requests[0].httpMethod == "POST")
    }

    @Test func omitsContentTypeWhenNoBody() async throws {
        let (client, transport) = makeClient(
            auth: .bearer(token: "t"),
            responses: [.init(statusCode: 200, data: Data(#"{"id":1}"#.utf8))]
        )
        let _: Dummy = try await client.send(Endpoint(path: "/servers"))

        let requests = await transport.recordedRequests
        #expect(requests[0].value(forHTTPHeaderField: "Content-Type") == nil)
    }

    @Test func neverPutsTokenInURL() async throws {
        let (client, transport) = makeClient(
            auth: .bearer(token: "super-secret"),
            responses: [.init(statusCode: 200, data: Data(#"{"id":1}"#.utf8))]
        )
        let _: Dummy = try await client.send(Endpoint(path: "/servers"))

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString.contains("super-secret") == false)
    }
}
