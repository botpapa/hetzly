import Foundation
import HetznerKit

/// Formatting and derivation helpers shared across the Dedicated (Robot)
/// feature. Kept free of view code so it stays trivially testable, mirroring
/// `ServerDetailSupport` for the Cloud side.
enum DedicatedSupport {
    /// Formats Robot's `paid_until` (a bare `yyyy-MM-dd` date string) for
    /// display, or an em dash when absent/unparsable.
    static func paidUntilDisplay(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let date = formatter.date(from: raw) {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        return raw
    }

    /// Rescue-mode OS choices offered by `EnableDedicatedRescueSheet`.
    ///
    /// `RobotBootConfiguration.rescue` (and the standalone `rescue()` call)
    /// only carry `RobotRescue.os: String` — the *currently active* rescue
    /// OS, not a list of what's available to choose from — so there's no
    /// live "available distributions" endpoint this client surface exposes.
    /// This is Hetzner Robot's well-documented, effectively-static set of
    /// rescue system identifiers.
    static let rescueOSOptions = ["linux", "linuxold", "freebsd", "vkvm"]
}

extension RobotServer {
    /// Maps Robot's status (plus the separate `cancelled` flag) to the
    /// DesignSystem's coarse `ResourceStatus` used by `StatusDot`:
    /// cancelled always reads as "off" regardless of the underlying status.
    var resourceStatus: ResourceStatus {
        if cancelled { return .off }
        switch status {
        case .ready: return .running
        case .inProcess: return .transitioning
        case .unknown: return .unknown
        }
    }

    var statusDisplayName: String {
        if cancelled { return "Cancelled" }
        switch status {
        case .ready: return "Ready"
        case .inProcess: return "In Process"
        case .unknown: return "Unknown"
        }
    }

    /// `serverName` falls back to the product name when the server has
    /// never been given a custom hostname (Robot allows an empty name).
    var displayName: String {
        serverName.isEmpty ? product : serverName
    }
}

extension RobotResetType {
    /// `.title` and `.plainExplanation` are already provided by
    /// `HetznerKit.RobotResetType` itself — only the destructive-styling
    /// flag (an app-layer UI concern) is added here.
    var isDestructive: Bool {
        switch self {
        case .sw: false
        case .hw, .man: true
        }
    }
}
