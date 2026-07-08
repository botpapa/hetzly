import Foundation

/// Identifies a single server within a specific project — the navigation
/// payload from the Dashboard into Server Detail (Worker E). Defined here
/// per the module contract: Dashboard owns the route, Server Detail's
/// `.navigationDestination(for: ServerRoute.self)` mapping lives on
/// `DashboardView`.
struct ServerRoute: Hashable, Codable, Sendable {
    let projectID: UUID
    let serverID: Int
}
