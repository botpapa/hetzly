import XCTest

@MainActor
final class DashboardRefreshUITests: HetzlyUITestCase {
    /// Repro: pulling to refresh the dashboard must NOT blank the server list.
    func test_pullToRefresh_keepsServersVisible() {
        let app = launchSeeded()

        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 15))
        let web = element(labeled: "web-01", in: app)
        XCTAssertTrue(web.waitForExistence(timeout: 10))

        // Pull to refresh a few times.
        for _ in 0..<3 {
            let top = app.scrollViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            let low = app.scrollViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            top.press(forDuration: 0.1, thenDragTo: low)
            usleep(400_000)
            // web-01 must remain on screen throughout / after each refresh.
            XCTAssertTrue(
                element(labeled: "web-01", in: app).exists,
                "web-01 disappeared after a pull-to-refresh"
            )
        }

        // And after everything settles.
        XCTAssertTrue(element(labeled: "web-01", in: app).waitForExistence(timeout: 8))
    }
}
