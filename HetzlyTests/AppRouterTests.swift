import XCTest
@testable import Hetzly

/// Covers `AppRouter.handle(_:)` — the piece that turns a parsed
/// `DeepLink` into tab-selection + pending-route state. `DeepLinkParserTests`
/// covers turning a URL into a `DeepLink`; this covers what happens next.
/// UI-level coverage (does Dashboard actually navigate) is exercised by
/// `HetzlyUITests/DeepLinkUITests.swift`.
@MainActor
final class AppRouterTests: XCTestCase {
    private let route = ServerRoute(projectID: UUID(), serverID: 7)
    private let projectRoute = ProjectRoute(projectID: UUID())

    func test_serverLink_switchesToDashboard_andStashesPendingRoute() {
        let router = AppRouter()
        router.selectedTab = .settings

        router.handle(.server(route))

        XCTAssertEqual(router.selectedTab, .dashboard)
        XCTAssertEqual(router.pendingRoute, .server(route))
    }

    func test_projectLink_switchesToDashboard_andStashesPendingRoute() {
        let router = AppRouter()
        router.selectedTab = .resources

        router.handle(.project(projectRoute))

        XCTAssertEqual(router.selectedTab, .dashboard)
        XCTAssertEqual(router.pendingRoute, .project(projectRoute))
    }

    func test_dashboardLink_switchesTab_andSetsPendingRouteToResetPath() {
        let router = AppRouter()
        router.selectedTab = .costs

        router.handle(.dashboard)

        XCTAssertEqual(router.selectedTab, .dashboard)
        XCTAssertEqual(router.pendingRoute, .dashboard)
    }

    func test_costsLink_switchesTab_andClearsAnyPendingRoute() {
        let router = AppRouter()
        router.pendingRoute = .server(route)

        router.handle(.costs)

        XCTAssertEqual(router.selectedTab, .costs)
        XCTAssertNil(router.pendingRoute, "Costs has no destination to push onto a nav path, so nothing should stay pending")
    }

    func test_defaultRouter_startsOnDashboard_withNoPendingRoute() {
        let router = AppRouter()
        XCTAssertEqual(router.selectedTab, .dashboard)
        XCTAssertNil(router.pendingRoute)
    }
}
