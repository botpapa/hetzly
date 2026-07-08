import XCTest

@MainActor
final class SettingsUITests: HetzlyUITestCase {
    /// `UpdateTokenSheet` (`Hetzly/Features/Settings/UpdateTokenSheet.swift`,
    /// out of this worker's scope) validates the pasted token by building its
    /// own `CloudClient(token:)` directly — it does NOT route through
    /// `AppContainer.cloudClient(for:)`, so it never picks up the pre-cached
    /// `UITestTransport`-backed client `UITestSupport` seeded this project
    /// with. That means `validateToken()` inside the sheet makes a REAL
    /// network call. Submitting here would be flaky (network-dependent) at
    /// best and hang/fail outright in a sandboxed/offline CI run at worst, so
    /// this test deliberately stops at "the sheet presents correctly and can
    /// be dismissed" and does not exercise the submit-and-persist path. That
    /// path (`ProjectsStore.updateToken` + `AppContainer.invalidateCloudClient`
    /// actually running) is covered instead by
    /// `ProjectsStoreMultiProjectTests.test_updateToken_replacesStoredToken`
    /// at the unit level.
    ///
    /// Reaching the sheet exercises a context menu, which XCUITest has no
    /// direct "right-click" gesture for — `XCUIElement.press(forDuration:)`
    /// (a long press) is the standard substitute and is what triggers it here.
    func test_updateToken_flow_presentsSheetAndCancels() {
        let app = launchSeeded()

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))

        // Long-press the project's list CELL where possible (not an
        // `.any`-typed CONTAINS match, whose firstMatch can resolve to a
        // container view and press the wrong point). Context-menu
        // presentation is timing-sensitive in XCUITest, so the press is
        // retried a few times — a missed press leaves no menu, and pressing
        // again is idempotent.
        let projectCell = app.cells
            .containing(NSPredicate(format: "label CONTAINS[c] %@", "Demo Project"))
            .firstMatch
        let pressTarget = projectCell.waitForExistence(timeout: 10)
            ? projectCell
            : element(labeled: "Demo Project", in: app)
        XCTAssertTrue(pressTarget.waitForExistence(timeout: 10))

        let updateTokenMenuItem = app.buttons["Update Token"]
        var menuAppeared = false
        for attempt in 0..<3 {
            pressTarget.press(forDuration: 1.5)
            if updateTokenMenuItem.waitForExistence(timeout: 5) {
                menuAppeared = true
                break
            }
            // A partial/failed press can leave the row highlighted — tap a
            // neutral spot near the top to reset before retrying.
            if attempt < 2 {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
            }
        }
        XCTAssertTrue(menuAppeared, "Context menu should offer 'Update Token'")
        updateTokenMenuItem.tap()

        XCTAssertTrue(app.navigationBars["Update Token"].waitForExistence(timeout: 10))

        let tokenField = app.secureTextFields.firstMatch
        XCTAssertTrue(tokenField.waitForExistence(timeout: 5))
        tokenField.tap()
        tokenField.typeText("new-token-not-validated-offline")

        // Cancel rather than submit — see the class doc comment above:
        // submitting would hit the real network from inside the sheet.
        app.buttons["Cancel"].tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        // The sheet's dismissal shouldn't have touched the stored token —
        // the project row is still there, unchanged.
        XCTAssertTrue(element(labeled: "Demo Project", in: app).waitForExistence(timeout: 5))
    }
}
