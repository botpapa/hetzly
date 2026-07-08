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

    /// Two seeded projects each render their own dashboard section — each
    /// with a DISTINCT fixture server pair (Production: web-01/worker-02,
    /// Staging: api-01/cache-02 — see `UITestTransport.serverNames`), so
    /// this exercises genuine per-project fetch isolation rather than just
    /// two sections that happen to look identical. The create-server "+"
    /// button offers a project picker (menu) instead of jumping straight
    /// into the wizard, and the combined burn card renders.
    func test_dashboard_aggregatesMultipleProjects() {
        let app = launchMultiProject()

        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 15))

        // Both project sections render.
        XCTAssertTrue(element(labeled: "Production", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element(labeled: "Staging", in: app).waitForExistence(timeout: 10))

        // Production's fixture server renders...
        XCTAssertTrue(element(labeled: "web-01", in: app).waitForExistence(timeout: 10))
        // ...and Staging's DISTINCT fixture server renders too — proof the
        // two projects' fetches are genuinely isolated, not just both
        // showing the same default "web-01"/"worker-02" pair twice.
        XCTAssertTrue(element(labeled: "api-01", in: app).waitForExistence(timeout: 10))

        // Combined burn card is present (fixture pricing × 2 projects).
        XCTAssertTrue(element(labeled: "This Month", in: app).waitForExistence(timeout: 10))

        // With >1 project the toolbar "+" ("New") menu's "Create Server"
        // entry must present a nested project-picker submenu, not jump
        // straight into the wizard. Menu items live inside the menu popup's
        // collection view — scoping there is required because the
        // `ProjectFilterBar` chips on the dashboard beneath are ALSO buttons
        // labeled "Production"/"Staging", and an unscoped `app.buttons[...]`
        // tap fails the ambiguity check ("Multiple matching elements found").
        waitAndTap(element(labeled: "New", in: app))
        waitAndTap(app.collectionViews.buttons["Create Server"])
        XCTAssertTrue(app.collectionViews.buttons["Production"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.collectionViews.buttons["Staging"].waitForExistence(timeout: 5))

        // Choosing a project opens the wizard for it.
        waitAndTap(app.collectionViews.buttons["Staging"])
        XCTAssertTrue(
            element(identifier: "createServer.footer.primaryCTA", in: app).waitForExistence(timeout: 10),
            "Wizard should open after picking a project from the menu"
        )
    }

    /// `ProjectFilterBar`'s "Production" chip scopes the whole dashboard to
    /// that project: Staging's section header (uppercased "STAGING") and its
    /// distinct `api-01` fixture server disappear entirely, Production's
    /// `web-01` remains, and tapping "All" brings everything back.
    ///
    /// Matching is deliberately case-SENSITIVE throughout: the filter bar's
    /// "Staging" chip stays on screen while the section is filtered out, so
    /// the assertions must target the header's uppercased "STAGING" (and the
    /// chip tap must target lowercase-exact "Production" to not hit the
    /// "PRODUCTION" header link).
    func test_dashboard_projectFilter_scopesSections() {
        let app = launchMultiProject()

        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 15))
        XCTAssertTrue(element(labeled: "web-01", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element(labeled: "api-01", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(button(labelContainsCaseSensitive: "STAGING", in: app).waitForExistence(timeout: 10))

        // The chip renders the name as-is ("Production"); the section header
        // renders it uppercased ("PRODUCTION") — case-sensitive exact match
        // picks the chip.
        waitAndTap(button(exactLabel: "Production", in: app))

        // Staging's section header and its distinct fixture server drop out.
        // (The "Staging" filter CHIP intentionally stays — that's the whole
        // filter bar — which is why these assertions target the uppercased
        // header text and the server name, never the word "Staging" itself.)
        XCTAssertFalse(button(labelContainsCaseSensitive: "STAGING", in: app).waitForExistence(timeout: 3))
        XCTAssertFalse(element(labeled: "api-01", in: app).waitForExistence(timeout: 3))
        // Production's server remains.
        XCTAssertTrue(element(labeled: "web-01", in: app).waitForExistence(timeout: 5))

        // "All" restores both sections.
        waitAndTap(button(exactLabel: "All", in: app))
        XCTAssertTrue(button(labelContainsCaseSensitive: "STAGING", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element(labeled: "api-01", in: app).waitForExistence(timeout: 10))
    }

    /// The toolbar "New" menu's "Add Project" entry opens `AddProjectSheet`
    /// (title + API token field) rather than jumping into server creation.
    /// `AddProjectSheet` validates against the live network (constructs its
    /// own `CloudClient(token:)`, same as `UpdateTokenSheet` — see
    /// `SettingsUITests`'s doc comment), so this only covers presenting the
    /// sheet and canceling back out, not submit-and-persist.
    func test_dashboard_addProjectMenuEntry_presentsSheet() {
        let app = launchSeeded()

        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 15))

        waitAndTap(element(labeled: "New", in: app))
        // Menu row scoped to the popup's collection view (see
        // `CreateServerWizardUITests` for why the unscoped match flakes).
        waitAndTap(app.collectionViews.buttons["Add Project"])

        XCTAssertTrue(app.navigationBars["Add Project"].waitForExistence(timeout: 10))
        XCTAssertTrue(element(labeled: "API token", in: app).waitForExistence(timeout: 5))

        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 10))
    }

    /// `.searchable`'s query overrides the project-scope filter entirely
    /// rather than filtering within it: typing "api" against the
    /// multi-project fixture (Production: web-01/worker-02, Staging:
    /// api-01/cache-02) surfaces Staging's `api-01` in the flat "Results"
    /// list while Production's `web-01` drops out — proof search searches
    /// every project, not just whichever one happens to be scoped.
    func test_dashboard_search_filtersAcrossProjects() {
        let app = launchMultiProject()

        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 15))
        XCTAssertTrue(element(labeled: "web-01", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element(labeled: "api-01", in: app).waitForExistence(timeout: 10))

        let searchField = app.searchFields.firstMatch
        waitAndTap(searchField)
        searchField.typeText("api")

        XCTAssertTrue(element(labeled: "api-01", in: app).waitForExistence(timeout: 10))
        XCTAssertFalse(element(labeled: "web-01", in: app).waitForExistence(timeout: 3))
    }

    /// Long-pressing a dashboard row opens its `.contextMenu` with the row
    /// quick actions — asserting on "Copy IPv4" (present on every row,
    /// unlike the contextual power actions which depend on server status)
    /// is enough to prove the menu itself wires up, without needing to fire
    /// an action (which would hit the fixture's power-action endpoints).
    func test_dashboard_rowContextMenu_showsQuickActions() {
        let app = launchSeeded()

        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 15))
        let webRow = element(labeled: "web-01", in: app)
        XCTAssertTrue(webRow.waitForExistence(timeout: 10))

        // Long-press via the row's center coordinate to open its
        // `.contextMenu`. The row is a `Button` (not a `NavigationLink`)
        // precisely so this long-press opens the menu rather than racing a
        // navigation gesture — see `DashboardView.serverRow`.
        webRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.3)

        XCTAssertTrue(app.buttons["Copy IPv4"].waitForExistence(timeout: 8))

        // Dismiss without selecting anything, so the pasteboard/haptic path
        // never fires — tap a spot away from both the row and the menu.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.05)).tap()
    }
}
