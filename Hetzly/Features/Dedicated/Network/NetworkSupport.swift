import Foundation
import HetznerKit

/// Formatting/validation helpers shared across the vSwitch + Failover IP UI,
/// mirroring `DedicatedSupport`'s role for the plain-server side of the
/// Dedicated tab. Built against the real `RobotClient+VSwitch`/
/// `RobotClient+Failover` extensions (`Packages/HetznerKit/Sources/HetznerKit/RobotAPI/`)
/// per `CONTRACTS.md`'s "Robot vSwitch + failover (worker F2)" entry.
enum NetworkSupport {
    /// Hetzner Robot's documented vSwitch VLAN ID range.
    static let vlanRange = 4000...4091

    static func isValidVLAN(_ vlan: Int) -> Bool {
        vlanRange.contains(vlan)
    }

    /// Robot allows any non-empty vSwitch name up to 255 characters.
    static func isValidVSwitchName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 255
    }
}

// MARK: - vSwitch server status

extension RobotVSwitchServer {
    /// Maps `RobotVSwitchConnectionStatus` to the DesignSystem's coarse
    /// `ResourceStatus` used by `StatusDot`.
    var resourceStatus: ResourceStatus {
        switch status {
        case .ready: .running
        case .inProcess: .transitioning
        case .failed: .error
        case .unknown: .unknown
        }
    }

    var statusDisplayName: String {
        switch status {
        case .ready: "Ready"
        case .inProcess: "In Process"
        case .failed: "Failed"
        case .unknown: "Unknown"
        }
    }
}

extension RobotVSwitch {
    /// Cancelled vSwitches always read as "off" in list rows, mirroring
    /// `RobotServer.resourceStatus`'s cancelled-overrides-everything rule.
    var resourceStatus: ResourceStatus {
        cancelled ? .off : .running
    }
}
