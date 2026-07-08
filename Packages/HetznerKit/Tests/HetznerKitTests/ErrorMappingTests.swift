import Foundation
import Testing
@testable import HetznerKit

private struct Item: Decodable, Sendable, Equatable {
    let id: Int
    let name: String
}

@Suite("Error mapping and decoding")
struct ErrorMappingTests {
    private func makeClient(responses: [MockTransport.ScriptedResponse]) -> HetznerHTTPClient {
        let transport = MockTransport(responses: responses)
        let configuration = APIConfiguration(
            baseURL: URL(string: "https://api.hetzner.cloud/v1")!,
            auth: .bearer(token: "t")
        )
        return HetznerHTTPClient(
            configuration: configuration,
            transport: transport,
            rateLimiter: RateLimiter(budget: 1000, window: 60)
        )
    }

    @Test func decodesSuccessResponse() async throws {
        let client = makeClient(responses: [
            .init(statusCode: 200, data: Data(#"{"id":1,"name":"srv"}"#.utf8))
        ])
        let item: Item = try await client.send(Endpoint(path: "/x"))
        #expect(item == Item(id: 1, name: "srv"))
    }

    @Test func decodesErrorEnvelopeAsAPIError() async throws {
        let client = makeClient(responses: [
            .init(statusCode: 400, data: Data(#"{"error":{"code":"invalid_input","message":"bad field"}}"#.utf8))
        ])
        do {
            let _: Item = try await client.send(Endpoint(path: "/x"))
            Issue.record("Expected an error to be thrown")
        } catch HetznerAPIError.api(let code, let message) {
            #expect(code == "invalid_input")
            #expect(message == "bad field")
        }
    }

    @Test func mapsUnauthorized() async throws {
        let client = makeClient(responses: [.init(statusCode: 401, data: Data())])
        do {
            let _: Item = try await client.send(Endpoint(path: "/x"))
            Issue.record("Expected an error to be thrown")
        } catch HetznerAPIError.unauthorized {
            #expect(HetznerAPIError.unauthorized.userMessage.isEmpty == false)
        }
    }

    @Test func mapsForbiddenWithMessage() async throws {
        let client = makeClient(responses: [
            .init(statusCode: 403, data: Data(#"{"error":{"code":"forbidden","message":"no access"}}"#.utf8))
        ])
        do {
            let _: Item = try await client.send(Endpoint(path: "/x"))
            Issue.record("Expected an error to be thrown")
        } catch HetznerAPIError.forbidden(let message) {
            #expect(message == "no access")
        }
    }

    @Test func mapsNotFound() async throws {
        let client = makeClient(responses: [.init(statusCode: 404, data: Data())])
        do {
            let _: Item = try await client.send(Endpoint(path: "/x"))
            Issue.record("Expected an error to be thrown")
        } catch HetznerAPIError.notFound {
            // expected
        }
    }

    @Test func mapsRateLimitedWithRetryAfter() async throws {
        let client = makeClient(responses: [
            .init(statusCode: 429, data: Data(), headers: ["Retry-After": "42"])
        ])
        do {
            let _: Item = try await client.send(Endpoint(path: "/x"))
            Issue.record("Expected an error to be thrown")
        } catch HetznerAPIError.rateLimited(let retryAfter) {
            #expect(retryAfter == 42)
        }
    }

    @Test func malformedJSONProducesDecodingError() async throws {
        let client = makeClient(responses: [
            .init(statusCode: 200, data: Data("not json".utf8))
        ])
        do {
            let _: Item = try await client.send(Endpoint(path: "/x"))
            Issue.record("Expected an error to be thrown")
        } catch HetznerAPIError.decoding {
            // expected
        }
    }

    @Test func sendExpectingNoContentSucceedsOn204() async throws {
        let client = makeClient(responses: [.init(statusCode: 204, data: Data())])
        try await client.sendExpectingNoContent(Endpoint(method: .delete, path: "/x/1"))
    }

    @Test func userMessagesAreHumanReadable() {
        #expect(HetznerAPIError.unauthorized.userMessage == "Your API token was rejected. It may have been revoked.")
        #expect(HetznerAPIError.notFound.userMessage.contains("could not be found"))
        #expect(HetznerAPIError.http(status: 500).userMessage.contains("500"))
    }

    @Test func forbiddenUserMessageIncludesReadOnlyTokenGuidance() {
        let withoutMessage = HetznerAPIError.forbidden(message: nil).userMessage
        #expect(withoutMessage == "You don't have permission for that. If this project uses a Read-only token, replace it with a Read & Write token.")

        let withMessage = HetznerAPIError.forbidden(message: "no access").userMessage
        #expect(withMessage.contains("no access"))
        #expect(withMessage.contains("Read-only token"))
        #expect(withMessage.contains("Read & Write token"))
    }

    @Test func isAuthErrorAndIsPermissionErrorFlagsAreMutuallyExclusive() {
        #expect(HetznerAPIError.unauthorized.isAuthError == true)
        #expect(HetznerAPIError.unauthorized.isPermissionError == false)

        #expect(HetznerAPIError.forbidden(message: nil).isPermissionError == true)
        #expect(HetznerAPIError.forbidden(message: nil).isAuthError == false)

        #expect(HetznerAPIError.notFound.isAuthError == false)
        #expect(HetznerAPIError.notFound.isPermissionError == false)
    }
}
