import XCTest

/// Shared launch helpers for `HetzlyUITests`. Each test launches its own
/// `XCUIApplication`, passing the launch-environment flag that
/// `UITestSupport` (Debug-only, in the app target) reads at startup to swap
/// in an in-memory `AppContainer` — either seeded with a demo project whose
/// `CloudClient` is routed through canned fixtures (`launchSeeded()`), or
/// left empty so onboarding shows (`launchEmpty()`). Neither path ever
/// touches the network.
@MainActor
class HetzlyUITestCase: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches with a pre-seeded "Demo Project": two fixture servers
    /// (`web-01` running, `worker-02` off) and a full create-server catalog
    /// (locations, images, server types, SSH keys, networks, firewalls,
    /// pricing) — see `UITestFixtures`.
    @discardableResult
    func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HETZLY_UITEST"] = "1"
        app.launch()
        return app
    }

    /// Launches with TWO pre-seeded projects ("Production" and "Staging"),
    /// each backed by its own fixture client — exercises multi-project
    /// aggregation (per-project dashboard sections, combined cost burn).
    @discardableResult
    func launchMultiProject() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HETZLY_UITEST_MULTI"] = "1"
        app.launch()
        return app
    }

    /// Launches with an empty in-memory store — no projects, so `RootView`
    /// shows `OnboardingView`.
    @discardableResult
    func launchEmpty() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HETZLY_UITEST_EMPTY"] = "1"
        app.launch()
        return app
    }

    /// Finds the first element (of any type) whose accessibility label
    /// contains `text`, case-insensitively. SwiftUI collapses `Button` /
    /// `NavigationLink` subtrees into a single accessibility element whose
    /// label is usually — but not reliably exactly — the concatenation of
    /// its text content, so a `CONTAINS[c]` predicate over "any" element type
    /// is far less brittle here than guessing whether something surfaces as
    /// `.staticText` vs `.button` vs `.link`, or matches a label exactly.
    func element(labeled text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", text))
            .firstMatch
    }

    /// Looks up an element by exact `accessibilityIdentifier`, regardless of
    /// its underlying XCUIElement type.
    func element(identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// Finds the first BUTTON whose label matches `exactLabel`
    /// case-SENSITIVELY. The case-sensitivity is the whole point: the
    /// dashboard renders the same project name twice — `ProjectFilterBar`'s
    /// chip (label exactly "Production") and the project section header
    /// (whose `SectionLabel` renders/labels the uppercased "PRODUCTION") —
    /// so any case-insensitive exact match (`==[c]`) is ambiguous between
    /// them, while plain `==` cleanly picks one or the other depending on
    /// the casing the caller passes.
    func button(exactLabel: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "label == %@", exactLabel))
            .firstMatch
    }

    /// Finds the first BUTTON whose label CONTAINS `text` case-SENSITIVELY —
    /// see `button(exactLabel:in:)` for why case-sensitive matching matters
    /// on the dashboard. Used for the section-header NavigationLinks, whose
    /// label starts with the uppercased project name ("PRODUCTION") but may
    /// carry additional accessibility text from sibling views.
    func button(labelContainsCaseSensitive text: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", text))
            .firstMatch
    }

    /// Waits for `element` to exist, fails loudly (with source location) if
    /// it never appears, then taps it.
    func waitAndTap(
        _ element: XCUIElement,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "Expected element to exist before tapping: \(element)",
            file: file,
            line: line
        )
        element.tap()
    }
}
