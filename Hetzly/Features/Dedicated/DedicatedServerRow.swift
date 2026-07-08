import HetznerKit
import SwiftUI

/// A single dedicated server's row on `DedicatedView`: status, name
/// (falling back to the product name when unset), product/DC chips, and the
/// primary IPv4 in monospace. Kept as a plain presentation view — its parent
/// wraps it in a `NavigationLink(value: RobotServerRoute(...))`.
struct DedicatedServerRow: View {
    let server: RobotServer

    var body: some View {
        GlassCard(interactive: true) {
            HStack(spacing: Spacing.unit * 3) {
                StatusDot(server.resourceStatus)

                VStack(alignment: .leading, spacing: Spacing.unit) {
                    Text(server.displayName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(HetzlyColors.textPrimary)

                    HStack(spacing: Spacing.unit * 2) {
                        GlassChip(server.product)
                        GlassChip(server.dc)
                    }

                    if let ip = server.serverIP {
                        Text(ip)
                            .hetzlyMonoNumbers()
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(HetzlyColors.textSecondary)
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        VStack(spacing: Spacing.unit * 3) {
            DedicatedServerRow(server: DedicatedPreviewFixtures.server)
            DedicatedServerRow(server: DedicatedPreviewFixtures.inProcessServer)
            DedicatedServerRow(server: DedicatedPreviewFixtures.cancelledServer)
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
