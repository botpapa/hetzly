import Foundation
import Observation

/// The main tabs `MainTabView` renders, in display order. Mirrors the
/// `Tab`s built there — kept as its own type (rather than reusing e.g. a
/// string) so `AppRouter.selectedTab` is a `TabView(selection:)`-friendly,
/// exhaustively-switchable value.
enum AppTab: Hashable, Sendable {
    case dashboard, resources, dedicated, costs, settings
}

/// App-wide navigation state driven by deep links (`hetzly://…`, widget
/// taps, Shortcuts): which tab is selected, plus a one-shot "pending route"
/// that the tab responsible for a route (currently always Dashboard — it
/// already owns `.navigationDestination(for: ServerRoute.self)` and
/// `.navigationDestination(for: ProjectRoute.self)`) consumes and clears.
///
/// Deliberately NOT a general replacement for each feature stack's own
/// `NavigationPath` — Dashboard keeps its own `@State private var
/// navigationPath` for in-app navigation (row taps, context-menu "View
/// Details", etc.) exactly as before. `pendingRoute` is only ever written by
/// `handle(_:)` and only ever read/cleared by the one view that owns the
/// matching destination, so there's exactly one writer and one reader per
/// route kind — no risk of two navigation sources fighting over the same
/// path.
///
/// Injected via `.environment(router)` from `HetzlyApp`, alongside
/// `AppContainer`.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .dashboard

    /// Set by `handle(_:)` for routes that need to push something once the
    /// owning tab is visible; cleared by that tab's view after consuming it.
    /// `nil` most of the time — only briefly non-nil between a deep link
    /// arriving and the destination view's `onChange` picking it up.
    var pendingRoute: DeepLink?

    init() {}

    /// Applies a parsed deep link: switches to the right tab and, for routes
    /// that name a specific destination, stashes it in `pendingRoute` for
    /// that tab to push onto its navigation path.
    func handle(_ link: DeepLink) {
        switch link {
        case .server, .project:
            selectedTab = .dashboard
            pendingRoute = link
        case .dashboard:
            selectedTab = .dashboard
            pendingRoute = link
        case .costs:
            selectedTab = .costs
            pendingRoute = nil
        }
    }
}
