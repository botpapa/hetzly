import XCTest

@MainActor
final class DashboardUITests: HetzlyUITestCase {
    /// Demo Project's two fixture servers render on launch, and tapping the
    /// running one navigates to Server Detail, whose hero card shows its
    /// fixture public IPv4 — then navigating back lands on the dashboard
    /// again. Exercises `AppContainer.makeForUITesting` end to end for the
    /// read-only surfaces (no create/mutate calls involved).
    func test_dashboard_showsServers_and_navigatesToDetail() {
        let app = launchSeeded()

        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 15))
        XCTAssertTrue(element(labeled: "Demo Project", in: app).waitForExistence(timeout: 10))

        let webRow = element(labeled: "web-01", in: app)
        waitAndTap(webRow)

        // Server Detail's hero card shows the running fixture server's
        // public IPv4 (95.216.1.10 — see `UITestFixtures`).
        XCTAssertTrue(element(labeled: "95.216.1.10", in: app).waitForExistence(timeout: 10))

        // Standard leading nav-bar back button.
        app.navigationBars.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 10))
        XCTAssertTrue(element(labeled: "Demo Project", in: app).waitForExistence(timeout: 10))
    }
}
