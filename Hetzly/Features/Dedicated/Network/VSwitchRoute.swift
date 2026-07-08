import Foundation

/// Identifies a single Robot vSwitch within a specific Robot account — the
/// navigation payload from `VSwitchListView` into `VSwitchDetailView`.
/// Mirrors `RobotServerRoute`.
struct VSwitchRoute: Hashable, Codable, Sendable {
    let accountID: UUID
    let vSwitchID: Int
}
