import XCTest

@MainActor
final class OnboardingUITests: HetzlyUITestCase {
    /// Launching with an empty in-memory store (no seeded project) shows
    /// `OnboardingView`'s hero, never the main tab shell — the counterpart to
    /// `DashboardUITests`' seeded launch, verifying `RootView`'s
    /// has-projects switch both ways.
    func test_onboarding_appears_withoutSeed() {
        let app = launchEmpty()

        XCTAssertTrue(element(labeled: "Hetzly", in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(element(labeled: "Add your first project", in: app).waitForExistence(timeout: 5))

        // The main app shell must not have appeared instead.
        XCTAssertFalse(app.navigationBars["Dashboard"].exists)
    }
}
