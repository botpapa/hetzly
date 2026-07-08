import SwiftUI

/// The main app shell once at least one project exists: Dashboard,
/// Resources hub, (conditionally) Dedicated, Costs, and Settings.
struct MainTabView: View {
    @Environment(AppContainer.self) private var container
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        // `selection:` bound to `AppRouter.selectedTab` so a `hetzly://`
        // deep link (or a widget/Shortcut tap) can switch tabs from outside
        // the tab bar itself — see `AppRouter.handle(_:)`. Each `Tab` names
        // its `AppTab` case via `value:`; tapping the bar still just writes
        // straight into the same binding, same as any other selection-bound
        // `TabView`.
        TabView(selection: $router.selectedTab) {
            Tab("Dashboard", systemImage: "square.grid.2x2", value: AppTab.dashboard) {
                DashboardView()
            }

            Tab("Resources", systemImage: "cube.box", value: AppTab.resources) {
                ResourcesHubView()
            }

            // Hidden until at least one Robot account is configured — with
            // none, `DedicatedView` only ever shows its own "add an account
            // in Settings" empty state, so the tab itself is dead weight.
            // `container.robotAccountsStore` is `@Observable`, so adding the
            // first account (in Settings) reveals this tab live, no relaunch
            // needed; removing the last one hides it again the same way.
            if !container.robotAccountsStore.accounts.isEmpty {
                Tab("Dedicated", systemImage: "server.rack", value: AppTab.dedicated) {
                    DedicatedView()
                }
            }

            Tab("Costs", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.costs) {
                CostsView()
            }

            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

#Preview {
    MainTabView()
        .environment(AppContainer.makeDefault())
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}
