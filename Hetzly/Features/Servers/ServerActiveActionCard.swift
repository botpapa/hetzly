import SwiftUI

/// Progress card shown under the action row while a power action is in
/// flight, e.g. "Rebooting… 40%" with an accent-tinted progress bar. Shows
/// `MascotView(.work)` alongside it when the mascot is enabled in Settings.
struct ServerActiveActionCard: View {
    let activeAction: ServerDetailViewModel.ActiveAction
    var mascotEnabled: Bool = true

    var body: some View {
        GlassCard {
            HStack(spacing: Spacing.unit * 4) {
                if mascotEnabled {
                    MascotView(state: .work, scale: 2)
                }
                VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                    Text("\(activeAction.kind.progressVerb)… \(activeAction.progress)%")
                        .hetzlyMonoNumbers()
                        .foregroundStyle(HetzlyColors.textPrimary)
                    ProgressView(value: Double(activeAction.progress), total: 100)
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
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
