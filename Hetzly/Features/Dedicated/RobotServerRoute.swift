import Foundation

/// Identifies a single Robot (dedicated) server within a specific Robot
/// account — the navigation payload from `DedicatedView` into
/// `DedicatedServerDetailView`. Mirrors Dashboard's `ServerRoute` for the
/// Cloud side.
struct RobotServerRoute: Hashable, Codable, Sendable {
    let accountID: UUID
    let serverNumber: Int
}
