import HetznerKit
import SwiftUI

/// RESCUE section for a dedicated server: a status row plus the enable/
/// disable entry point. Enabling opens `EnableDedicatedRescueSheet` (OS +
/// SSH key selection); disabling goes through a plain confirm dialog owned
/// by `DedicatedServerDetailView`. Mirrors `ServerRescueSection` for the
/// Cloud side.
struct DedicatedRescueSection: View {
    let rescue: RobotRescue?
    let rescueState: DedicatedServerDetailViewModel.LoadState
    var onEnable: () -> Void
    var onDisable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            SectionLabel("Rescue Mode")

            GlassCard {
                switch rescueState {
                case .idle, .loading:
                    HStack(spacing: Spacing.unit * 2) {
                        ProgressView()
                        Text("Loading rescue status…").caption()
                    }
                case .failed(let message):
                    Text(message).caption()
                case .loaded:
                    content
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let active = rescue?.active ?? false
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            HStack(spacing: Spacing.unit * 3) {
                Image(systemName: "lifepreserver")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(active ? HetzlyColors.statusTransitioning : HetzlyColors.textTertiary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(active ? "Rescue mode armed" : "Rescue mode off")
                        .bodyPrimary()
                    Text(
                        active
                            ? "The server boots into the rescue system on its next restart."
                            : "Boot a minimal recovery system to fix an unbootable server."
                    )
                    .caption()
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            Button(action: active ? onDisable : onEnable) {
                Text(active ? "Disable Rescue Mode" : "Enable Rescue Mode")
                    .frame(maxWidth: .infinity)
            }
            .secondaryCTAStyle()
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        VStack(spacing: Spacing.unit * 4) {
            DedicatedRescueSection(rescue: DedicatedPreviewFixtures.rescueInactive, rescueState: .loaded, onEnable: {}, onDisable: {})
            DedicatedRescueSection(rescue: DedicatedPreviewFixtures.rescueActive, rescueState: .loaded, onEnable: {}, onDisable: {})
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
