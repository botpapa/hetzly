import Foundation

/// The three ways Robot can reset a dedicated server. Ordered from gentlest
/// to most invasive; not every server supports every type (see
/// `RobotResetInfo.availableTypes`).
public enum RobotResetType: String, Codable, Sendable, CaseIterable, Equatable {
    case sw
    case hw
    case man

    /// Short, human-facing label for pickers/menus.
    public var title: String {
        switch self {
        case .sw: return "Software Reset"
        case .hw: return "Hardware Reset"
        case .man: return "Manual Reset"
        }
    }

    /// One-sentence explanation of what actually happens on the hardware,
    /// suitable for a confirmation sheet.
    public var plainExplanation: String {
        switch self {
        case .sw:
            return "Sends CTRL+ALT+DEL — a graceful software reboot, no power cut."
        case .hw:
            return "Presses the reset button — immediate hard restart, unsaved data is lost."
        case .man:
            return "A technician manually power-cycles the server. Use when nothing else responds."
        }
    }
}

/// `GET /reset/{server-number}` — which reset types this server supports and
/// its current operating status, as reported by Robot's out-of-band tooling.
public struct RobotResetInfo: Codable, Sendable, Equatable {
    public let serverNumber: Int?
    /// Raw wire values (e.g. `["sw", "hw", "man"]`); unrecognized entries are
    /// dropped by `availableTypes` rather than failing the whole decode.
    public let type: [String]
    public let operatingStatus: String?

    enum CodingKeys: String, CodingKey {
        case serverNumber = "server_number"
        case type
        case operatingStatus = "operating_status"
    }

    public init(serverNumber: Int?, type: [String], operatingStatus: String?) {
        self.serverNumber = serverNumber
        self.type = type
        self.operatingStatus = operatingStatus
    }

    /// `type` mapped to `RobotResetType`, silently dropping any value Robot
    /// introduces later that this client doesn't recognize yet.
    public var availableTypes: [RobotResetType] {
        type.compactMap { RobotResetType(rawValue: $0) }
    }
}
