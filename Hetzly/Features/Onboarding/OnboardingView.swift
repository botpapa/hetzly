import SwiftUI

/// First-run hero screen shown when the user has no projects yet. Presents
/// `AddProjectSheet` — the same sheet Settings uses later to add another
/// project — to collect the first one.
struct OnboardingView: View {
    @Environment(AppContainer.self) private var container

    @State private var isPresentingAddProject = false

    var body: some View {
        ZStack {
            CanvasBackground()

            VStack(spacing: Spacing.unit * 6) {
                Spacer(minLength: 0)

                if container.settings.mascotEnabled {
                    MascotView(state: .idle, scale: 4)
                } else {
                    ProgressView().controlSize(.large)
                }

                VStack(spacing: Spacing.unit * 3) {
                    Text("Hetzly")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(HetzlyColors.textPrimary)

                    Text("Your Hetzner Cloud servers, at a glance and in your pocket.")
                        .bodySecondary()
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }

                Spacer(minLength: 0)

                VStack(spacing: Spacing.unit * 4) {
                    PrimaryCTA(title: "Add your first project") {
                        isPresentingAddProject = true
                    }
                    .frame(maxWidth: .infinity)

                    Text("Independent third-party app, not affiliated with Hetzner Online GmbH.")
                        .caption()
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.vertical, Spacing.screenMargin * 2)
        }
        .sheet(isPresented: $isPresentingAddProject) {
            AddProjectSheet()
        }
    }
}

#Preview {
    OnboardingView()
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}

#Preview("Appearance: Light") {
    OnboardingView()
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.light)
}
