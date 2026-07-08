import Foundation

/// Identifies a single project's command-center screen — the navigation
/// payload used anywhere in the app that links into `ProjectDetailView`
/// (Dashboard and Costs project section headers, per the multi-project wave
/// contract). Defined here per the module contract: Projects owns the route,
/// and every `NavigationStack` that wants to push into it registers its own
/// `.navigationDestination(for: ProjectRoute.self)` mapping.
struct ProjectRoute: Hashable, Codable, Sendable {
    let projectID: UUID
}
