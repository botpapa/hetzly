import Foundation

/// Thin, opinionated layer over `KeychainStore` that gives every feature one
/// obvious place to store and fetch secrets, keyed by well-known service
/// names. No secret ever passes through here in a form that could be logged.
enum TokenVault {
    /// Service name for Hetzner Cloud project API tokens.
    /// Account = the project's UUID string.
    static let cloudTokenService = "com.hetzly.cloud-token"

    /// Service name for Hetzner Robot credentials.
    /// Account = the Robot account id string.
    static let robotCredentialsService = "com.hetzly.robot-credentials"

    private static let store = KeychainStore()

    // MARK: - Cloud project tokens

    /// Saves the Hetzner Cloud API token for the project identified by `projectID`.
    static func saveCloudToken(_ token: String, projectID: String) throws {
        try store.saveString(token, service: cloudTokenService, account: projectID)
    }

    /// Reads the Hetzner Cloud API token for the project identified by `projectID`.
    static func cloudToken(projectID: String) throws -> String? {
        try store.readString(service: cloudTokenService, account: projectID)
    }

    /// Deletes the Hetzner Cloud API token for the project identified by `projectID`.
    static func deleteCloudToken(projectID: String) throws {
        try store.delete(service: cloudTokenService, account: projectID)
    }

    // MARK: - Robot credentials

    /// Username/password pair for a Hetzner Robot account, stored as JSON.
    struct RobotCredentials: Codable, Sendable, Equatable {
        let username: String
        let password: String
    }

    /// Saves Robot `credentials` for the account identified by `accountID`.
    static func saveRobotCredentials(_ credentials: RobotCredentials, accountID: String) throws {
        let data = try JSONEncoder().encode(credentials)
        try store.save(data, service: robotCredentialsService, account: accountID)
    }

    /// Reads Robot credentials for the account identified by `accountID`.
    static func robotCredentials(accountID: String) throws -> RobotCredentials? {
        guard let data = try store.read(service: robotCredentialsService, account: accountID) else {
            return nil
        }
        return try JSONDecoder().decode(RobotCredentials.self, from: data)
    }

    /// Deletes Robot credentials for the account identified by `accountID`.
    static func deleteRobotCredentials(accountID: String) throws {
        try store.delete(service: robotCredentialsService, account: accountID)
    }
}
