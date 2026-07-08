import XCTest

/// Covers the SP2 Control/Analytics restructure: `ServerDetailTabPicker`'s
/// glass segmented control switches the page between the "everything that
/// acts on the server" panel (Control — Danger Zone included, at the very
/// bottom) and the metrics-only panel (Analytics — CPU/network/disk charts).
/// The two panels are mutually exclusive, so this asserts a Control-only
/// element (Danger Zone) disappears under Analytics and the chart shows,
/// then that switching back restores Control's content.
@MainActor
final class ServerDetailTabsUITests: HetzlyUITestCase {
    func test_serverDetail_segmentedControl_switchesControlAndAnalytics() {
        let app = launchSeeded()

        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 15))
        waitAndTap(element(labeled: "web-01", in: app))

        // Hero card is reachable regardless of tab — starts on Control.
        XCTAssertTrue(element(labeled: "95.216.1.10", in: app).waitForExistence(timeout: 10))

        // Control is the default tab: Danger Zone (the last section) is
        // reachable by scrolling; the metrics chart is not present at all.
        var dangerZone = element(labeled: "Danger Zone", in: app)
        for _ in 0..<5 where !dangerZone.exists {
            app.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(dangerZone.waitForExistence(timeout: 5), "Danger Zone should be reachable on the default Control tab")
        XCTAssertFalse(element(labeled: "CPU chart", in: app).waitForExistence(timeout: 3), "Charts should not render on the Control tab")

        // Switch to Analytics: the CPU chart appears, Danger Zone hides.
        waitAndTap(element(labeled: "Analytics", in: app))
        XCTAssertTrue(element(labeled: "CPU chart", in: app).waitForExistence(timeout: 10))
        XCTAssertFalse(element(labeled: "Danger Zone", in: app).waitForExistence(timeout: 3), "Danger Zone should hide under Analytics")

        // Switch back to Control: Danger Zone reachable again, chart hides.
        waitAndTap(element(labeled: "Control", in: app))
        dangerZone = element(labeled: "Danger Zone", in: app)
        for _ in 0..<5 where !dangerZone.exists {
            app.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(dangerZone.waitForExistence(timeout: 5), "Danger Zone should be reachable again after switching back to Control")
        XCTAssertFalse(element(labeled: "CPU chart", in: app).waitForExistence(timeout: 3), "Charts should hide again on the Control tab")
    }
}
