import HetznerKit
import SwiftUI

/// One firewall rule row: color-coded protocol chip, monospaced port (or
/// "any" for port-less protocols), wrapping CIDR chips, and an optional
/// description caption. Tap-to-edit and swipe-to-delete are attached by the
/// caller (`FirewallDetailView`, inside a `List`).
struct FirewallRuleRow: View {
    let rule: FirewallRule

    private var addresses: [String] {
        rule.direction == .inbound ? rule.sourceIPs : rule.destinationIPs
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                HStack(spacing: Spacing.unit * 2) {
                    protocolChip
                    Text(rule.networkProtocol.showsPort ? (rule.port ?? "any") : "any")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(HetzlyColors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HetzlyColors.textTertiary)
                }

                if !addresses.isEmpty {
                    FlowLayout(spacing: Spacing.unit * 1.5) {
                        ForEach(addresses, id: \.self) { address in
                            Text(address)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(HetzlyColors.textSecondary)
                                .padding(.horizontal, Spacing.unit * 2)
                                .padding(.vertical, Spacing.unit)
                                .background(Capsule(style: .continuous).fill(Color.white.opacity(0.06)))
                        }
                    }
                }

                if let description = rule.description, !description.isEmpty {
                    Text(description).caption()
                }
            }
        }
    }

    private var protocolChip: some View {
        HStack(spacing: Spacing.unit) {
            Circle().fill(rule.networkProtocol.tint).frame(width: 6, height: 6)
            Text(rule.networkProtocol.displayName)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(rule.networkProtocol.tint)
        .padding(.horizontal, Spacing.unit * 2.5)
        .padding(.vertical, Spacing.unit)
        .background(Capsule(style: .continuous).fill(rule.networkProtocol.tint.opacity(0.15)))
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        ScrollView {
            VStack(spacing: Spacing.unit * 3) {
                ForEach(Array(FirewallPreviewFixtures.webFirewall.rules.enumerated()), id: \.offset) { _, rule in
                    FirewallRuleRow(rule: rule)
                }
            }
            .padding(Spacing.screenMargin)
        }
    }
    .preferredColorScheme(.dark)
}
