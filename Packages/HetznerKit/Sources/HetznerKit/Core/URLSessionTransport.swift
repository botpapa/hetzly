import Foundation

/// Production `HTTPTransport` conformance backed by `URLSession`.
///
/// Uses an ephemeral session configuration so credentialed responses are never
/// written to disk or shared cookie/cache storage, and disables connectivity
/// waiting so requests fail fast instead of hanging indefinitely offline.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HetznerAPIError.transport(underlying: "Received a non-HTTP response.")
        }
        return (data, httpResponse)
    }
}
