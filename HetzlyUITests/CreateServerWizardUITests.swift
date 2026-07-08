import XCTest

@MainActor
final class CreateServerWizardUITests: HetzlyUITestCase {
    /// Full happy path through the four-step create-server wizard against
    /// `UITestFixtures`' canned catalog: pick the first location card (fsn1,
    /// alphabetically first by city — "Falkenstein"), the ubuntu flavor and
    /// its 24.04 version chip, the first (cheapest) server type row (cx22),
    /// then submit step 4 with the auto-generated name — through the
    /// "creating" phase to "succeeded" (`Done` button), landing back on the
    /// dashboard.
    func test_createServerWizard_happyPath() {
        let app = launchSeeded()

        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 15))

        // Toolbar "New" menu → "Create Server" (single project: jumps
        // straight into the wizard). The menu item is scoped to the menu
        // popup's collection view — an unscoped `.any`-typed CONTAINS match
        // can resolve to a non-tappable wrapper mid-animation and silently
        // miss (observed as a flake), whereas the collection-view button is
        // the real tappable menu row.
        waitAndTap(element(labeled: "New", in: app))
        waitAndTap(app.collectionViews.buttons["Create Server"])

        // Step 1 — Location: first card (fsn1 / Falkenstein).
        waitAndTap(element(identifier: "createServer.locationCard.fsn1", in: app), timeout: 15)
        waitAndTap(element(identifier: "createServer.footer.primaryCTA", in: app))

        // Step 2 — Image: expand the ubuntu flavor, then pick the 24.04 chip
        // explicitly (image id 101 in `UITestFixtures`).
        waitAndTap(element(identifier: "createServer.flavorRow.ubuntu", in: app))
        waitAndTap(element(identifier: "createServer.versionChip.101", in: app))
        waitAndTap(element(identifier: "createServer.footer.primaryCTA", in: app))

        // Step 3 — Type: first (cheapest) row, cx22 (id 22).
        waitAndTap(element(identifier: "createServer.typeRow.22", in: app))
        waitAndTap(element(identifier: "createServer.footer.primaryCTA", in: app))

        // Step 4 — Configure: name is prefilled by `NameGenerator` on init,
        // nothing else required. Same footer identifier, now reading
        // "Create Server · €.../mo".
        let createCTA = element(identifier: "createServer.footer.primaryCTA", in: app)
        XCTAssertTrue(createCTA.waitForExistence(timeout: 10))
        createCTA.tap()

        // Creating phase: `UITestTransport`'s `POST /servers` + `GET
        // /actions/{id}` resolve near-instantly, but assert the transient
        // state showed up at some point isn't required for correctness —
        // only that we land on success. Go straight to asserting the
        // succeeded phase's Done button appears.
        let doneButton = element(identifier: "createServer.result.doneButton", in: app)
        XCTAssertTrue(doneButton.waitForExistence(timeout: 20))
        doneButton.tap()

        // Sheet dismisses, back on the dashboard.
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 10))
        XCTAssertTrue(element(labeled: "Demo Project", in: app).waitForExistence(timeout: 10))
    }

    /// `UITestFixtures`' `/ssh_keys` always returns one key ("uitest-key"),
    /// so step 4 never renders the "No SSH keys yet" empty state in this
    /// harness — it renders the populated key list instead, which now ends
    /// in a secondary "Add another key" row wiring up the shared
    /// `SSHKeyAddSheet` in-flow. Assert that row exists rather than the
    /// empty-state's own "Add SSH Key" button, since the fixture data can't
    /// exercise the zero-keys path.
    func test_createServerWizard_step4ShowsAddAnotherKeyButton() {
        let app = launchSeeded()

        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 15))

        waitAndTap(element(labeled: "New", in: app))
        waitAndTap(app.collectionViews.buttons["Create Server"])

        waitAndTap(element(identifier: "createServer.locationCard.fsn1", in: app), timeout: 15)
        waitAndTap(element(identifier: "createServer.footer.primaryCTA", in: app))

        waitAndTap(element(identifier: "createServer.flavorRow.ubuntu", in: app))
        waitAndTap(element(identifier: "createServer.versionChip.101", in: app))
        waitAndTap(element(identifier: "createServer.footer.primaryCTA", in: app))

        waitAndTap(element(identifier: "createServer.typeRow.22", in: app))
        waitAndTap(element(identifier: "createServer.footer.primaryCTA", in: app))

        let addAnotherKeyButton = element(identifier: "createServer.sshKeys.addAnotherButton", in: app)
        XCTAssertTrue(addAnotherKeyButton.waitForExistence(timeout: 10))
    }
}
