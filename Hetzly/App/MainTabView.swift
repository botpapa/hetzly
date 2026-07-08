import SwiftUI

/// The main app shell once at least one project exists: a four-tab layout
/// hosting the M1 dashboard plus M2 placeholders for Resources and Costs.
struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Dashboard", systemImage: "square.grid.2x2") {
                DashboardView()
            }

            Tab("Resources", systemImage: "cube.box") {
                ComingSoonTabView(
                    title: "Resources",
                    message: "Volumes, networks, and firewalls arrive in M2."
                )
            }

            Tab("Costs", systemImage: "chart.line.uptrend.xyaxis") {
                ComingSoonTabView(
                    title: "Costs",
                    message: "Cost breakdowns and projections arrive in M2."
                )
            }

            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

/// Shared empty-state placeholder for tabs whose feature set lands in a
/// later milestone.
private struct ComingSoonTabView: View {
    let title: String
    let message: String

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()

                VStack(spacing: Spacing.unit * 5) {
                    MascotView(state: .peek, scale: 4)

                    VStack(spacing: Spacing.unit * 2) {
                        SectionLabel(title)
                        Text(message)
                            .bodySecondary()
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: 280)
                }
                .padding(Spacing.screenMargin)
            }
            .navigationTitle(title)
        }
    }
}

#Preview {
    MainTabView()
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}

#Preview("Coming soon tab") {
    ComingSoonTabView(title: "Resources", message: "Volumes, networks, and firewalls arrive in M2.")
        .preferredColorScheme(.dark)
}
