import HetznerKit
import SwiftUI

/// A firewall's row in `FirewallListView`: name, rule count, applied-to
/// count.
struct FirewallRowView: View {
    let firewall: Firewall

    var body: some View {
        GlassCard(interactive: true) {
            HStack(spacing: Spacing.unit * 3) {
                Image(systemName: "checkerboard.shield")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(HetzlyColors.accent)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.unit) {
                    Text(firewall.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(HetzlyColors.textPrimary)

                    HStack(spacing: Spacing.unit * 2) {
                        GlassChip("\(firewall.rules.count) rule\(firewall.rules.count == 1 ? "" : "s")")
                        GlassChip(
                            "\(firewall.appliedTo.count) applied",
                            systemImage: "server.rack"
                        )
                    }
                }

                Spacer(minLength: Spacing.unit * 2)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HetzlyColors.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        VStack(spacing: Spacing.unit * 3) {
            FirewallRowView(firewall: FirewallPreviewFixtures.webFirewall)
            FirewallRowView(firewall: FirewallPreviewFixtures.bareFirewall)
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
