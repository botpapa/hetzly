import SwiftData
import SwiftUI

@main
struct HetzlyApp: App {
    @State private var container = AppContainer.makeDefault()

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
