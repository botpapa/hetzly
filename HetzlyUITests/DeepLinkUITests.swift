import XCTest

/// Exercises `hetzly://` deep links end to end: `AppRouter` switching tabs
/// and pushing a route, consumed by `DashboardView`'s `.onChange(of:
/// router.pendingRoute)`.
///
/// XCTest/XCUIApplication has no supported API to simulate a real system
/// `onOpenURL` delivery (driving it via Safari + the "Open in Hetzly?"
/// system alert is possible in principle but flaky and slow in CI, and
/// depends on install/signing plumbing this repo's `CODE_SIGNING_ALLOWED=NO`
/// verification builds don't have) — so these launch the app with
/// `HETZLY_UITEST_DEEPLINK_URL` set, which `HetzlyApp`'s `#if DEBUG`-only
/// `uiTestLaunchDeepLink(container:)` reads and feeds through the exact same
/// `DeepLinkParser.parse` → `AppRouter.handle` path a real `onOpenURL` call
/// would use. `DeepLinkParserTests`/`AppRouterTests` (`HetzlyTests`) cover
/// the parsing and routing logic directly; this covers that the resulting
/// UI actually lands where it should.
@MainActor
final class DeepLinkUITests: HetzlyUITestCase {
    /// `UITestFixtures.runningServerID` (`web-01`, IPv4 95.216.1.10) — kept
    /// in sync manually since `HetzlyUITests` can't import the app target's
    /// `#if DEBUG`-only fixtures.
    private static let runningServerID = 5101

    private func launchSeeded(deepLink: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HETZLY_UITEST"] = "1"
        app.launchEnvironment["HETZLY_UITEST_DEEPLINK_URL"] = deepLink
        app.launch()
        return app
    }

    /// `hetzly://costs` switches off the default Dashboard tab straight to
    /// Costs on launch — proves `AppRouter.selectedTab` actually drives
    /// `MainTabView`'s `TabView(selection:)`.
    func test_costsDeepLink_landsOnCostsTab() {
        let app = launchSeeded(deepLink: "hetzly://costs")

        XCTAssertTrue(app.navigationBars["Costs"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.navigationBars["Dashboard"].exists)
    }

    /// `hetzly://server/{projectID}/5101` lands directly on Server Detail
    /// for the seeded demo project's running fixture server — proves the
    /// full chain: tab switch to Dashboard, `pendingRoute` consumed,
    /// `ServerRoute` pushed onto Dashboard's `NavigationPath`,
    /// `.navigationDestination(for: ServerRoute.self)` resolving to
    /// `ServerDetailView`. `{projectID}` is substituted by `HetzlyApp` for
    /// the demo project's real (randomly-generated per launch) id — see
    /// `uiTestLaunchDeepLink(container:)`.
    func test_serverDeepLink_landsOnServerDetail() {
        let app = launchSeeded(deepLink: "hetzly://server/{projectID}/\(Self.runningServerID)")

        // Server Detail's hero card shows the running fixture server's
        // public IPv4 (see `UITestFixtures.runningServerJSON`).
        XCTAssertTrue(element(labeled: "95.216.1.10", in: app).waitForExistence(timeout: 15))

        // Landed there without ever seeing the dashboard's own server list
        // rendered underneath first getting tapped — the nav bar shows the
        // server's name, not "Dashboard".
        XCTAssertTrue(element(labeled: "web-01", in: app).waitForExistence(timeout: 5))
    }

    /// `hetzly://project/{projectID}` lands on `ProjectDetailView`, whose
    /// nav title is the project's name.
    func test_projectDeepLink_landsOnProjectDetail() {
        let app = launchSeeded(deepLink: "hetzly://project/{projectID}")

        XCTAssertTrue(app.navigationBars["Demo Project"].waitForExistence(timeout: 15))
    }
}
