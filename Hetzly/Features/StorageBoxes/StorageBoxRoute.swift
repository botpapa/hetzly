import Foundation

/// Identifies a single Storage Box within a specific Storage Box account —
/// the navigation payload from `StorageBoxesView` into
/// `StorageBoxDetailView`. Mirrors Dedicated's `RobotServerRoute` for the
/// Storage Box side.
struct StorageBoxRoute: Hashable, Codable, Sendable {
    let accountID: UUID
    let storageBoxID: Int
}
