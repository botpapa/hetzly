import Foundation

/// Errors surfaced by `HetznerHTTPClient`. `userMessage` is always a human
/// sentence suitable for direct display — never raw JSON or wire details.
public enum HetznerAPIError: Error, Sendable {
    case unauthorized
    case forbidden(message: String?)
    case notFound
    case rateLimited(retryAfter: TimeInterval?)
    case api(code: String, message: String)
    case http(status: Int)
    case decoding(underlying: String)
    case transport(underlying: String)
}

extension HetznerAPIError: LocalizedError {
    /// Shared guidance appended to every `.forbidden` message: the single
    /// most common cause of a 403 in this app is a Read-only token hitting
    /// a write endpoint, so callers get a concrete next step rather than
    /// just raw API text.
    private static let readOnlyTokenGuidance = "If this project uses a Read-only token, replace it with a Read & Write token."

    public var userMessage: String {
        switch self {
        case .unauthorized:
            return "Your API token was rejected. It may have been revoked."
        case .forbidden(let message):
            if let message, !message.isEmpty {
                return "You don't have permission for that: \(message). \(Self.readOnlyTokenGuidance)"
            }
            return "You don't have permission for that. \(Self.readOnlyTokenGuidance)"
        case .notFound:
            return "The requested resource could not be found. It may have already been deleted."
        case .rateLimited(let retryAfter):
            if let retryAfter, retryAfter > 0 {
                return "Hetzner is rate-limiting requests. Try again in \(Int(retryAfter.rounded())) seconds."
            }
            return "Hetzner is rate-limiting requests. Please wait a moment and try again."
        case .api(_, let message):
            return message
        case .http(let status):
            return "The server returned an unexpected response (HTTP \(status))."
        case .decoding:
            return "The app couldn't understand the server's response. Please try again later."
        case .transport:
            return "A network error occurred. Please check your connection and try again."
        }
    }

    public var errorDescription: String? { userMessage }

    /// `true` for a rejected/revoked token (401) — the recoverable case
    /// where prompting for a fresh token actually fixes things, as opposed
    /// to `isPermissionError` (403) where the token is valid but under-
    /// scoped for the attempted action.
    public var isAuthError: Bool {
        if case .unauthorized = self { return true }
        return false
    }

    /// `true` when the request was rejected for lacking permission (403) —
    /// most commonly a Read-only token hitting a write endpoint.
    public var isPermissionError: Bool {
        if case .forbidden = self { return true }
        return false
    }
}
