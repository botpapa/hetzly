import Foundation

/// HTTP verbs used by the Hetzner Cloud API.
public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}
