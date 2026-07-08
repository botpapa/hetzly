import Foundation

/// A minimal, tolerant representation of an arbitrary JSON value. Used for
/// wire fields whose shape varies by server/account (e.g. `authorized_key`
/// entries under rescue, which Robot has been observed to emit as either
/// bare fingerprint strings or `{"key": {...}}` objects) — decoding never
/// fails just because this field's shape doesn't match what we expected.
public indirect enum RobotJSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: RobotJSONValue])
    case array([RobotJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: RobotJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([RobotJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

/// Rescue system state, from `GET/POST/DELETE /boot/{server-number}/rescue`.
///
/// `password` is only present in the response to `POST` (enabling rescue
/// mode generates a fresh one-time root password) — it is SECRET and must
/// never be logged or persisted outside the Keychain.
public struct RobotRescue: Codable, Sendable, Equatable {
    public let serverIP: String?
    public let serverNumber: Int?
    public let os: String
    public let active: Bool
    /// SECRET — never log. Present only right after enabling rescue mode.
    public let password: String?
    /// Loose passthrough of whatever shape `authorized_key` has on the wire.
    public let authorizedKey: [RobotJSONValue]?

    enum CodingKeys: String, CodingKey {
        case serverIP = "server_ip"
        case serverNumber = "server_number"
        case os, active, password
        case authorizedKey = "authorized_key"
    }

    public init(
        serverIP: String? = nil,
        serverNumber: Int? = nil,
        os: String,
        active: Bool,
        password: String? = nil,
        authorizedKey: [RobotJSONValue]? = nil
    ) {
        self.serverIP = serverIP
        self.serverNumber = serverNumber
        self.os = os
        self.active = active
        self.password = password
        self.authorizedKey = authorizedKey
    }
}

/// One boot-manager entry (`linux` or `vnc`) under `GET /boot/{n}`. Robot
/// returns `dist` as either a bare string or an array of strings depending
/// on the endpoint/account — decoded via the tolerant `RobotStringOrArray`
/// helper (shared with `RobotProduct` in `OrderingModels.swift`) and
/// normalized to `[String]` here.
public struct RobotBootDistOption: Codable, Sendable, Equatable {
    public let dist: [String]
    public let active: Bool
    /// SECRET — never log. Present only while this boot option is active.
    public let password: String?

    enum CodingKeys: String, CodingKey { case dist, active, password }

    public init(dist: [String], active: Bool, password: String? = nil) {
        self.dist = dist
        self.active = active
        self.password = password
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dist = try container.decodeIfPresent(RobotStringOrArray.self, forKey: .dist)?.values ?? []
        active = try container.decodeIfPresent(Bool.self, forKey: .active) ?? false
        password = try container.decodeIfPresent(String.self, forKey: .password)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dist, forKey: .dist)
        try container.encode(active, forKey: .active)
        try container.encodeIfPresent(password, forKey: .password)
    }
}

/// `GET /boot/{server-number}` — the full boot-manager summary (rescue,
/// Linux installation image, and VNC installation image availability/state).
/// Never cached — like `RobotRescue`, entries here can carry passwords and
/// mutate server-side as a side effect of being read.
public struct RobotBootConfiguration: Codable, Sendable, Equatable {
    public let rescue: RobotRescue?
    public let linux: RobotBootDistOption?
    public let vnc: RobotBootDistOption?

    enum CodingKeys: String, CodingKey { case rescue, linux, vnc }

    public init(rescue: RobotRescue? = nil, linux: RobotBootDistOption? = nil, vnc: RobotBootDistOption? = nil) {
        self.rescue = rescue
        self.linux = linux
        self.vnc = vnc
    }
}
