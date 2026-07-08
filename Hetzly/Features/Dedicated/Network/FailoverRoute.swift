import Foundation

/// Identifies a single Robot failover IP within a specific Robot account —
/// the navigation payload from `FailoverListView` into `FailoverDetailView`.
/// Mirrors `RobotServerRoute`. `ip` is the failover IP address itself
/// (Robot's own identifier for the resource — there is no separate numeric
/// ID).
struct FailoverRoute: Hashable, Codable, Sendable {
    let accountID: UUID
    let ip: String
}
