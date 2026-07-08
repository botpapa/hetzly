import Foundation
@testable import HetznerKit

/// Scriptable `HTTPTransport` for tests: returns queued responses in order
/// and records every request it was asked to send.
actor MockTransport: HTTPTransport {
    struct ScriptedResponse: Sendable {
        let statusCode: Int
        let data: Data
        let headers: [String: String]

        init(statusCode: Int, data: Data, headers: [String: String] = [:]) {
            self.statusCode = statusCode
            self.data = data
            self.headers = headers
        }
    }

    private var responses: [ScriptedResponse]
    private(set) var recordedRequests: [URLRequest] = []

    init(responses: [ScriptedResponse]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        recordedRequests.append(request)

        guard !responses.isEmpty else {
            throw URLError(.unknown)
        }
        let next = responses.removeFirst()

        let url = request.url ?? URL(string: "https://example.invalid")!
        guard let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: next.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: next.headers
        ) else {
            throw URLError(.badServerResponse)
        }
        return (next.data, httpResponse)
    }
}
