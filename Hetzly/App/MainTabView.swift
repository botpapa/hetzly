import SwiftUI

/// The main app shell once at least one project exists: Dashboard,
/// Resources hub, Costs, and Settings.
struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Dashboard", systemImage: "square.grid.2x2") {
                DashboardView()
            }

            Tab("Resources", systemImage: "cube.box") {
                ResourcesHubView()
            }

            Tab("Dedicated", systemImage: "server.rack") {
                DedicatedView()
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
