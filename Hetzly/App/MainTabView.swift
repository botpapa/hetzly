import SwiftUI

/// The main app shell once at least one project exists: Dashboard,
/// Resources hub, (conditionally) Dedicated, Costs, and Settings.
struct MainTabView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        TabView {
            Tab("Dashboard", systemImage: "square.grid.2x2") {
                DashboardView()
            }

            Tab("Resources", systemImage: "cube.box") {
                ResourcesHubView()
            }

            // Hidden until at least one Robot account is configured — with
            // none, `DedicatedView` only ever shows its own "add an account
            // in Settings" empty state, so the tab itself is dead weight.
            // `container.robotAccountsStore` is `@Observable`, so adding the
            // first account (in Settings) reveals this tab live, no relaunch
            // needed; removing the last one hides it again the same way.
            if !container.robotAccountsStore.accounts.isEmpty {
                Tab("Dedicated", systemImage: "server.rack") {
                    DedicatedView()
                }
            }

            Tab("Costs", systemImage: "chart.line.uptrend.xyaxis") {
                CostsView()
            }

            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

#Preview {
    MainTabView()
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}
