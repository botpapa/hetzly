import Foundation

/// Executes `Endpoint`s against the Hetzner Cloud API: builds requests,
/// respects the injected `RateLimiter`, and maps non-2xx responses to
/// `HetznerAPIError`. The API token is never written into a URL or logged.
public actor HetznerHTTPClient {
    private let configuration: APIConfiguration
    private let transport: HTTPTransport
    private let rateLimiter: RateLimiter
    private let decoder: JSONDecoder

    public init(configuration: APIConfiguration, transport: HTTPTransport, rateLimiter: RateLimiter) {
        self.configuration = configuration
        self.transport = transport
        self.rateLimiter = rateLimiter
        self.decoder = makeHetznerJSONDecoder()
    }

    /// Sends `endpoint` and decodes the response body as `T`.
    public func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        let (data, _) = try await performRequest(endpoint)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HetznerAPIError.decoding(underlying: String(describing: error))
        }
    }

    /// Sends `endpoint` and discards the response body (e.g. 204 No Content).
    public func sendExpectingNoContent(_ endpoint: Endpoint) async throws {
        _ = try await performRequest(endpoint)
    }

    /// Sends `endpoint` and returns the raw response body, for callers (like
    /// pagination) that need to decode with additional context.
    func fetchPageData(_ endpoint: Endpoint) async throws -> Data {
        let (data, _) = try await performRequest(endpoint)
        return data
    }

    // MARK: - Request execution

    private func performRequest(_ endpoint: Endpoint) async throws -> (Data, HTTPURLResponse) {
        await rateLimiter.waitForSlot()

        let request = try makeRequest(for: endpoint)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch let error as HetznerAPIError {
            throw error
        } catch {
            throw HetznerAPIError.transport(underlying: error.localizedDescription)
        }

        await rateLimiter.record(response: response)

        guard (200..<300).contains(response.statusCode) else {
            throw mapError(status: response.statusCode, data: data, response: response)
        }

        return (data, response)
    }

    private func makeRequest(for endpoint: Endpoint) throws -> URLRequest {
        let trimmedPath = endpoint.path.hasPrefix("/") ? String(endpoint.path.dropFirst()) : endpoint.path
        let url = configuration.baseURL.appendingPathComponent(trimmedPath)

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw HetznerAPIError.transport(underlying: "Failed to construct a valid request URL.")
        }
        if !endpoint.query.isEmpty {
            components.queryItems = endpoint.query
        }
        guard let finalURL = components.url else {
            throw HetznerAPIError.transport(underlying: "Failed to construct a valid request URL.")
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if endpoint.body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue(configuration.auth.headerValue, forHTTPHeaderField: "Authorization")

        return request
    }

    // MARK: - Error mapping

    private func mapError(status: Int, data: Data, response: HTTPURLResponse) -> HetznerAPIError {
        switch status {
        case 401:
            return .unauthorized
        case 403:
            return .forbidden(message: decodeErrorEnvelope(data)?.message)
        case 404:
            return .notFound
        case 429:
            return .rateLimited(retryAfter: retryAfterInterval(from: response))
        default:
            if let envelope = decodeErrorEnvelope(data) {
                return .api(code: envelope.code, message: envelope.message)
            }
            return .http(status: status)
        }
    }

    private func decodeErrorEnvelope(_ data: Data) -> HetznerErrorEnvelope.Body? {
        try? JSONDecoder().decode(HetznerErrorEnvelope.self, from: data).error
    }

    private func retryAfterInterval(from response: HTTPURLResponse) -> TimeInterval? {
        if let retryAfterHeader = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = TimeInterval(retryAfterHeader) {
            return seconds
        }
        if let resetHeader = response.value(forHTTPHeaderField: "RateLimit-Reset"),
           let resetEpoch = TimeInterval(resetHeader) {
            return max(0, resetEpoch - Date().timeIntervalSince1970)
        }
        return nil
    }
}
