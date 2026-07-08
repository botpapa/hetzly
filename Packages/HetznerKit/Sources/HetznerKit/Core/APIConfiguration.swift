import Foundation

/// Configuration required to talk to the Hetzner Cloud API.
public struct APIConfiguration: Sendable {
    public let baseURL: URL
    public let auth: AuthMethod

    public init(baseURL: URL, auth: AuthMethod) {
        self.baseURL = baseURL
        self.auth = auth
    }
}
