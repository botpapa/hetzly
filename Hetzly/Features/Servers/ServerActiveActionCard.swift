import SwiftUI

/// Progress card shown under the action row while a power *or* management
/// action is in flight, e.g. "Rebooting… 40%" with an accent-tinted progress
/// bar. Shows `MascotView(.work)` alongside it when the mascot is enabled in
/// Settings.
///
/// Takes plain `progressVerb`/`progress` rather than a `PowerAction` so the
/// same card renders both `ServerDetailViewModel.ActiveAction` (power row)
/// and `ServerDetailViewModel.ManagementActiveAction` (backups, rescue,
/// rebuild, rescale's multi-step chain, ...) without this view knowing about
/// either action enum.
struct ServerActiveActionCard: View {
    let progressVerb: String
    let progress: Int
    var mascotEnabled: Bool = true

    init(progressVerb: String, progress: Int, mascotEnabled: Bool = true) {
        self.progressVerb = progressVerb
        self.progress = progress
        self.mascotEnabled = mascotEnabled
    }

    /// Convenience initializer for the power-action row's `ActiveAction`.
    init(activeAction: ServerDetailViewModel.ActiveAction, mascotEnabled: Bool = true) {
        self.progressVerb = activeAction.kind.progressVerb
        self.progress = activeAction.progress
        self.mascotEnabled = mascotEnabled
    }

    /// Convenience initializer for the management-action flow's
    /// `ManagementActiveAction`.
    init(managementActiveAction: ServerDetailViewModel.ManagementActiveAction, mascotEnabled: Bool = true) {
        self.progressVerb = managementActiveAction.stepLabel
        self.progress = managementActiveAction.progress
        self.mascotEnabled = mascotEnabled
    }

    var body: some View {
        GlassCard {
            HStack(spacing: Spacing.unit * 4) {
                if mascotEnabled {
                    MascotView(state: .work, scale: 2)
                }
                VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                    Text("\(progressVerb)… \(progress)%")
                        .hetzlyMonoNumbers()
                        .foregroundStyle(HetzlyColors.textPrimary)
                    ProgressView(value: Double(progress), total: 100)
                        .tint(HetzlyColors.accent)
                }
            }
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        VStack(spacing: Spacing.unit * 4) {
            ServerActiveActionCard(
                activeAction: .init(kind: .reboot, progress: 40),
                mascotEnabled: true
            )
            ServerActiveActionCard(
                activeAction: .init(kind: .powerOff, progress: 70),
                mascotEnabled: false
            )
            ServerActiveActionCard(
                managementActiveAction: .init(stepLabel: "Shutting Down", progress: 55),
                mascotEnabled: true
            )
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
