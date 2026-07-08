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
                .modelContainer(container.modelContainer)
                .preferredColorScheme(preferredColorScheme)
                .privacyOverlay()
        }
    }
}
