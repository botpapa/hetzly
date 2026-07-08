import Foundation

/// A Hetzner asynchronous operation (power actions, delete, rebuild, ...).
public struct Action: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let command: String
    public let status: ActionStatus
    public let progress: Int
    public let started: Date
    public let finished: Date?
    public let error: ActionError?
    public let resources: [ActionResource]

    enum CodingKeys: String, CodingKey {
        case id, command, status, progress, started, finished, error, resources
    }

    public init(
        id: Int,
        command: String,
        status: ActionStatus,
        progress: Int,
        started: Date,
        finished: Date?,
        error: ActionError?,
        resources: [ActionResource]
    ) {
        self.id = id
        self.command = command
        self.status = status
        self.progress = progress
        self.started = started
        self.finished = finished
        self.error = error
        self.resources = resources
    }
}

/// Unknown wire values decode to `.unknown` instead of throwing.
public enum ActionStatus: String, Codable, Sendable, Equatable {
    case running, success, error
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ActionStatus(rawValue: raw) ?? .unknown
    }
}

public struct ActionError: Codable, Sendable, Equatable {
    public let code: String
    public let message: String

    enum CodingKeys: String, CodingKey { case code, message }

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct ActionResource: Codable, Sendable, Equatable {
    public let id: Int
    public let type: String

    enum CodingKeys: String, CodingKey { case id, type }

    public init(id: Int, type: String) {
        self.id = id
        self.type = type
    }
}

/// Wire envelope for endpoints that return `{"action": {...}}`.
struct ActionEnvelope: Decodable, Sendable {
    let action: Action
}
