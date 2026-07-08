import Foundation
import Observation

/// The single project a Resources/Costs screen is currently scoped to.
///
/// Owned by `ResourcesHubView` (one `@State` instance) and injected via
/// `.environment` so every pushed list/detail screen — plus Worker B3's
/// Firewalls/Load Balancers/DNS screens and Costs — reads the same selection
/// via `@Environment(ResourcesProjectSelection.self)`, per the module
/// contract ("Shared per-project selection for Resources/Costs").
@MainActor
@Observable
final class ResourcesProjectSelection {
    var projectID: UUID?

    init(projectID: UUID? = nil) {
        self.projectID = projectID
    }
}
