import Foundation

/// Describes a single Hetzner Cloud API call, independent of transport.
public struct Endpoint: Sendable {
    public var method: HTTPMethod
    /// Path relative to the API base URL, e.g. "/servers". A leading slash is optional.
    public var path: String
    public var query: [URLQueryItem]
    public var body: Data?

    public init(method: HTTPMethod = .get, path: String, query: [URLQueryItem] = [], body: Data? = nil) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
    }
}
