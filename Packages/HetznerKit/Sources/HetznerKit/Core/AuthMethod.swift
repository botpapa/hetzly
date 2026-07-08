import Foundation

/// How requests to the Hetzner API are authenticated.
public enum AuthMethod: Sendable {
    case bearer(token: String)
    case basic(username: String, password: String)

    /// The value for the `Authorization` header. Never logged.
    var headerValue: String {
        switch self {
        case .bearer(let token):
            return "Bearer \(token)"
        case .basic(let username, let password):
            let credentials = "\(username):\(password)"
            let encoded = Data(credentials.utf8).base64EncodedString()
            return "Basic \(encoded)"
        }
    }
}
