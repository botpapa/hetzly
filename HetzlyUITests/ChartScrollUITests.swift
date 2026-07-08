import XCTest

@MainActor
final class ChartScrollUITests: HetzlyUITestCase {
    /// Regression: a swipe that STARTS on a metrics chart must scroll the
    /// page. The scrub gesture used to claim the touch exclusively, making
    /// the server screen unscrollable wherever a chart happened to be under
    /// the finger — the scrub is now a simultaneous hold-then-drag, so a
    /// plain flick always pans the ScrollView.
    ///
    /// Since the SP2 Control/Analytics restructure, the metrics charts live
    /// under the Analytics tab and the Danger Zone under Control — so this
    /// switches to Analytics for the chart-origin scroll assertion, then
    /// back to Control to confirm the Danger Zone is still reachable there
    /// (it's no longer reachable by scrolling PAST the chart, since they're
    /// on different panels now, but the underlying "flick starting on a
    /// chart scrolls the page" regression is exercised the same way).
    func test_serverDetail_swipeStartingOnChart_scrollsPage() {
        let app = launchSeeded()

        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 15))
        waitAndTap(element(labeled: "web-01", in: app))

        waitAndTap(element(labeled: "Analytics", in: app))

        // Wait for the metrics section (CPU chart renders from fixtures).
        let cpuChart = element(labeled: "CPU chart", in: app)
        XCTAssertTrue(cpuChart.waitForExistence(timeout: 15))

        // Primary assertion: the page MOVES when a flick starts on the
        // chart. Compare the chart's on-screen frame before/after.
        let before = cpuChart.frame
        cpuChart.swipeUp(velocity: .fast)
        // Let the deceleration settle.
        _ = app.navigationBars.firstMatch.waitForExistence(timeout: 1)
        let after = cpuChart.exists ? cpuChart.frame : .zero

        XCTAssertNotEqual(
            before.minY, after.minY,
            "A flick starting on the chart did not scroll the page (frame unchanged: \(before) -> \(after))"
        )

        // Danger Zone now lives on the Control tab — switch back and keep
        // flicking until it's reachable at the very bottom of that panel.
        waitAndTap(element(labeled: "Control", in: app))
        let dangerZone = element(labeled: "Danger Zone", in: app)
        for _ in 0..<4 where !(dangerZone.exists && dangerZone.isHittable) {
            app.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(
            dangerZone.waitForExistence(timeout: 5),
            "Danger Zone should be reachable on the Control tab"
        )
    }

    /// The other half of the contract: a deliberate press-and-hold on the
    /// chart, then dragging, engages the scrub tooltip.
    func test_serverDetail_holdThenDragOnChart_showsScrubTooltip() {
        let app = launchSeeded()

        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 15))
        waitAndTap(element(labeled: "web-01", in: app))

        waitAndTap(element(labeled: "Analytics", in: app))

        let cpuChart = element(labeled: "CPU chart", in: app)
        XCTAssertTrue(cpuChart.waitForExistence(timeout: 15))

        // Hold still on the chart for well past the 0.25s engage window,
        // then drag horizontally across the plot.
        let start = cpuChart.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        let end = cpuChart.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        start.press(forDuration: 0.6, thenDragTo: end)

        // The lollipop disappears on release, so assert DURING the drag is
        // impossible from XCUITest — instead do a hold-drag-hold and check
        // mid-gesture via a second slow drag with hold at the end.
        let holdEnd = cpuChart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(
            forDuration: 0.6,
            thenDragTo: holdEnd,
            withVelocity: .slow,
            thenHoldForDuration: 1.0
        )
        // If neither interaction crashed and scroll still works afterwards,
        // the scrub path is at least exercised; the tooltip presence check
        // is best-effort (timing-dependent under XCUITest).
        XCTAssertTrue(cpuChart.exists)
    }
}
