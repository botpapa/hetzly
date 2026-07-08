import XCTest

@MainActor
final class ProjectDetailUITests: HetzlyUITestCase {
    /// Tapping a Dashboard project section header pushes `ProjectDetailView`
    /// for that project (its burn card, server rows, and Manage section),
    /// tapping a server row from there pushes Server Detail (hero card shows
    /// the fixture's public IPv4), and backing out twice returns to the
    /// Dashboard. Exercises the `ProjectRoute` navigation wiring end to end.
    func test_projectDetail_opensFromSectionHeader() {
        let app = launchMultiProject()

        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 15))
        XCTAssertTrue(element(labeled: "Production", in: app).waitForExistence(timeout: 10))

        // The project section header's `SectionLabel` renders the name
        // uppercased ("PRODUCTION"), while `ProjectFilterBar`'s chip keeps
        // the original casing ("Production") — case-SENSITIVE matching on
        // the uppercased text is what disambiguates the header
        // NavigationLink from the chip (see
        // `HetzlyUITestCase.button(labelContainsCaseSensitive:in:)`).
        waitAndTap(button(labelContainsCaseSensitive: "PRODUCTION", in: app))

        // `ProjectDetailView`'s nav title is the project's own name.
        XCTAssertTrue(app.navigationBars["Production"].waitForExistence(timeout: 10))

        // Burn card, server row, and the Manage section (rename/update
        // token/remove) all render.
        XCTAssertTrue(element(labeled: "This Month", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element(labeled: "web-01", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element(labeled: "Manage", in: app).waitForExistence(timeout: 10))

        // Tapping the server row pushes Server Detail; its hero card shows
        // the running fixture server's public IPv4 (95.216.1.10 —
        // `UITestFixtures`).
        waitAndTap(element(labeled: "web-01", in: app))
        XCTAssertTrue(element(labeled: "95.216.1.10", in: app).waitForExistence(timeout: 10))

        // Back to Project Detail...
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Production"].waitForExistence(timeout: 10))

        // ...and back to the Dashboard.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 10))
    }
}
