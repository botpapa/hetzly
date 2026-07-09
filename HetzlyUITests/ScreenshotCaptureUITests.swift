import XCTest

/// Not a test — a scripted screenshot capture for the README / store listing.
/// Runs only when `HETZLY_SHOTS_DIR` (a host path) is set; navigates the
/// fixture app and writes real PNGs. Skipped in normal CI runs.
@MainActor
final class ScreenshotCaptureUITests: HetzlyUITestCase {
    private var shotsDir: String? { ProcessInfo.processInfo.environment["HETZLY_SHOTS_DIR"] }

    private func save(_ app: XCUIApplication, _ name: String) {
        guard let dir = shotsDir else { return }
        guard let png = app.windows.firstMatch.screenshot().image.pngData() else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        try? png.write(to: url)
    }

    func test_captureScreenshots() throws {
        try XCTSkipIf(shotsDir == nil, "Set HETZLY_SHOTS_DIR to capture screenshots.")

        let app = XCUIApplication()
        app.launchEnvironment["HETZLY_UITEST_MULTI"] = "1"
        app.launch()

        // 1. Dashboard (multi-project)
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 20))
        XCTAssertTrue(element(labeled: "web-01", in: app).waitForExistence(timeout: 10))
        sleep(1)
        save(app, "01-dashboard")

        // 2. Server detail — Control tab
        element(labeled: "web-01", in: app).firstMatch.tap()
        XCTAssertTrue(element(labeled: "95.216.1.10", in: app).waitForExistence(timeout: 10))
        sleep(1)
        save(app, "02-server-control")

        // 3. Server detail — Analytics tab
        let analytics = element(labeled: "Analytics", in: app)
        if analytics.waitForExistence(timeout: 5) {
            analytics.tap()
            _ = element(labeled: "CPU chart", in: app).waitForExistence(timeout: 8)
            sleep(1)
            save(app, "03-server-analytics")
        }

        // Back to dashboard
        app.navigationBars.buttons.element(boundBy: 0).tap()
        _ = app.navigationBars["Dashboard"].waitForExistence(timeout: 8)

        // 4. Costs tab
        app.tabBars.buttons["Costs"].tap()
        _ = app.navigationBars["Costs"].waitForExistence(timeout: 8)
        sleep(1)
        save(app, "04-costs")

        // 5. Resources tab
        app.tabBars.buttons["Resources"].tap()
        _ = app.navigationBars["Resources"].waitForExistence(timeout: 8)
        sleep(1)
        save(app, "05-resources")

        // 6. Settings tab
        app.tabBars.buttons["Settings"].tap()
        _ = app.navigationBars["Settings"].waitForExistence(timeout: 8)
        sleep(1)
        save(app, "06-settings")

        // 7. Create-server wizard (from dashboard "New" menu)
        app.tabBars.buttons["Dashboard"].tap()
        _ = app.navigationBars["Dashboard"].waitForExistence(timeout: 8)
        element(labeled: "New", in: app).firstMatch.tap()
        let createServer = element(labeled: "Create Server", in: app)
        if createServer.waitForExistence(timeout: 4) {
            createServer.tap()
            // a project submenu appears in multi-project mode
            let prod = app.buttons["Production"]
            if prod.waitForExistence(timeout: 3) { prod.tap() }
            if element(labeled: "Choose a Location", in: app).waitForExistence(timeout: 8) {
                sleep(1)
                save(app, "07-create-wizard")
            }
        }
    }
}
