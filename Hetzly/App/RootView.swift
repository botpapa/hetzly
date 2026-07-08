import SwiftUI

/// Top-level switch between the onboarding flow (no projects yet) and the
/// main app (`MainTabView`), driven by `AppContainer.projectsStore`.
struct RootView: View {
    @Environment(AppContainer.self) private var container

    private var hasProjects: Bool {
        !container.projectsStore.projects.isEmpty
    }

    var body: some View {
        ZStack {
            CanvasBackground()

            if hasProjects {
                MainTabView()
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: hasProjects)
    }
}

#Preview {
    RootView()
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}
