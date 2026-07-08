import SwiftData
import SwiftUI

@main
struct HetzlyApp: App {
    /// `UITestSupport.makeContainerIfRequested()` returns `nil` on every
    /// normal launch (Debug or Release) — it only builds a container when an
    /// explicit `HETZLY_UITEST`/`HETZLY_UITEST_EMPTY` launch-environment flag
    /// is set, which only `HetzlyUITests` ever sets. In Release builds the
    /// whole call compiles away (`UITestSupport` is `#if DEBUG`-only), so
    /// this line is exactly `AppContainer.makeDefault()` there.
    @State private var container = Self.makeContainer()

    /// Drives tab selection + pending-route state for `hetzly://` deep
    /// links (widgets, Shortcuts, automations) — see `AppRouter`.
    @State private var router = AppRouter()

    private static func makeContainer() -> AppContainer {
        #if DEBUG
        if let uiTestContainer = UITestSupport.makeContainerIfRequested() {
            return uiTestContainer
        }
        #endif
        return AppContainer.makeDefault()
    }

    private var preferredColorScheme: ColorScheme? {
        switch container.settings.appearance {
        case "system":
            return nil
        default:
            return .dark
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
                .environment(router)
                .modelContainer(container.modelContainer)
                .preferredColorScheme(preferredColorScheme)
                .privacyOverlay(enabled: container.settings.privacyShieldEnabled)
                .onOpenURL { url in
                    if let deepLink = DeepLinkParser.parse(url) {
                        router.handle(deepLink)
                    }
                }
                .task {
                    #if DEBUG
                    if let deepLink = Self.uiTestLaunchDeepLink(container: container) {
                        router.handle(deepLink)
                    }
                    #endif
                }
        }
    }

    #if DEBUG
    /// UI-test-only bridge for exercising the deep-link path end to end.
    /// XCTest/XCUIApplication has no supported API to simulate a real system
    /// `onOpenURL` delivery, so `HetzlyUITests` instead sets
    /// `HETZLY_UITEST_DEEPLINK_URL` before `-launch()` and this reads it —
    /// "a launch arg the app reads", same shape as `UITestSupport`'s
    /// existing `HETZLY_UITEST*` flags, just for deep links instead of data
    /// seeding. Compiles away entirely in Release builds.
    ///
    /// The demo project seeded by `UITestSupport` gets a random `UUID` each
    /// launch, which a test can't know ahead of time — callers write the
    /// literal token `{projectID}` in place of the UUID segment (e.g.
    /// `"hetzly://server/{projectID}/5101"`) and this substitutes the first
    /// seeded project's real id before handing the string to the same
    /// `DeepLinkParser` a real `onOpenURL` URL goes through.
    static func uiTestLaunchDeepLink(container: AppContainer) -> DeepLink? {
        guard let raw = ProcessInfo.processInfo.environment["HETZLY_UITEST_DEEPLINK_URL"] else { return nil }
        let projectIDToken = container.projectsStore.projects.first?.id.uuidString ?? ""
        let resolved = raw.replacingOccurrences(of: "{projectID}", with: projectIDToken)
        guard let url = URL(string: resolved) else { return nil }
        return DeepLinkParser.parse(url)
    }
    #endif
}
