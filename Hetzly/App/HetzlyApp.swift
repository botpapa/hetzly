import SwiftUI

@main
struct HetzlyApp: App {
    @AppStorage("appearance") private var appearance: String = "dark"

    private var preferredColorScheme: ColorScheme? {
        switch appearance {
        case "system":
            return nil
        default:
            return .dark
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(preferredColorScheme)
        }
    }
}
