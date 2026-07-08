import Foundation

/// Abstraction over URLSession so tests inject a mock transport.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
