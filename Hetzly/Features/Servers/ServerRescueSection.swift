import HetznerKit
import SwiftUI

/// RESCUE MODE section: a status row plus the enable/disable entry point.
/// Enabling opens `EnableRescueSheet` (SSH key selection); disabling goes
/// through the shared management confirm flow. Both are owned by
/// `ServerDetailView` via the callbacks here.
struct ServerRescueSection: View {
    let server: Server
    var onEnable: () -> Void
    var onDisable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            SectionLabel("Rescue Mode")

            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                    HStack(spacing: Spacing.unit * 3) {
                        Image(systemName: "lifepreserver")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(server.rescueEnabled ? HetzlyColors.statusTransitioning : HetzlyColors.textTertiary)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.rescueEnabled ? "Rescue mode armed" : "Rescue mode off")
                                .bodyPrimary()
                            Text(
                                server.rescueEnabled
                                    ? "The server boots into the rescue system on its next restart."
                                    : "Boot a minimal recovery system to fix an unbootable server."
                            )
                            .caption()
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }

                    Button(action: server.rescueEnabled ? onDisable : onEnable) {
                        Text(server.rescueEnabled ? "Disable Rescue Mode" : "Enable Rescue Mode")
                            .frame(maxWidth: .infinity)
                    }
                    .secondaryCTAStyle()
                }
            }
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        ServerRescueSection(server: PreviewFixtures.server, onEnable: {}, onDisable: {})
            .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
