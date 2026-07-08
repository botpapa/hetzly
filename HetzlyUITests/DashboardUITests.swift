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

    /// Two seeded projects each render their own dashboard section, with
    /// server rows under both, and the create-server "+" button offers a
    /// project picker (menu) instead of jumping straight into the wizard.
    /// Exercises the multi-project aggregation paths: per-project fetch
    /// isolation, section rendering, and the combined burn card.
    func test_dashboard_aggregatesMultipleProjects() {
        let app = launchMultiProject()

        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 15))

        // Both project sections render.
        XCTAssertTrue(element(labeled: "Production", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element(labeled: "Staging", in: app).waitForExistence(timeout: 10))

        // Server rows exist under both sections: the fixture set (web-01,
        // worker-02) appears once per project.
        let webRows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "web-01"))
        XCTAssertTrue(webRows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(webRows.count, 2, "Expected web-01 in both project sections")

        // Combined burn card is present (fixture pricing × 2 projects).
        XCTAssertTrue(element(labeled: "This Month", in: app).waitForExistence(timeout: 10))

        // With >1 project the "+" button must present the project menu, not
        // jump straight into the wizard.
        waitAndTap(element(labeled: "Create Server", in: app))
        XCTAssertTrue(app.buttons["Production"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Staging"].waitForExistence(timeout: 5))

        // Choosing a project opens the wizard for it.
        waitAndTap(app.buttons["Staging"])
        XCTAssertTrue(
            element(identifier: "createServer.footer.primaryCTA", in: app).waitForExistence(timeout: 10),
            "Wizard should open after picking a project from the menu"
        )
    }
}
