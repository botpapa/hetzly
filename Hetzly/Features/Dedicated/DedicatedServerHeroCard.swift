import HetznerKit
import SwiftUI
import UIKit

/// The hero glass card at the top of Dedicated Server Detail: status, name
/// (tap to rename), cancelled badge, product/DC chips, IPv4/IPv6
/// (tap-to-copy), paid-until, and traffic. Robot's `traffic` field is a
/// free-form string (`"unlimited"`, `"20 TB"`, …) — displayed verbatim, no
/// fake progress bar (Robot doesn't report usage-to-date).
struct DedicatedServerHeroCard: View {
    let server: RobotServer
    var onTapName: () -> Void

    @State private var didCopyIPv4 = false
    @State private var didCopyIPv6 = false
    @State private var copyHaptic = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 4) {
                HStack(spacing: Spacing.unit * 2) {
                    StatusDot(server.resourceStatus)
                    Text(server.statusDisplayName)
                        .bodySecondary()
                    Spacer()
                    if server.cancelled {
                        GlassChip("Cancelled", systemImage: "xmark.circle")
                    }
                }

                Button(action: onTapName) {
                    HStack(spacing: Spacing.unit * 2) {
                        Text(server.displayName)
                            .font(.system(size: 22, weight: .bold))
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                            .foregroundStyle(HetzlyColors.textPrimary)
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(HetzlyColors.textTertiary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(server.displayName), rename")
                .accessibilityHint("Double tap to rename this server")

                addressBlock

                chipRow

                VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                    DetailInfoRow(label: "Paid Until", value: DedicatedSupport.paidUntilDisplay(server.paidUntil))
                    DetailInfoRow(label: "Traffic", value: server.traffic)
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: copyHaptic)
    }

    @ViewBuilder
    private var addressBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.unit) {
            if let ipv4 = server.serverIP {
                Button(action: { copy(ipv4, isV4: true) }) {
                    HStack(spacing: Spacing.unit * 2) {
                        Text(ipv4)
                            .hetzlyMonoNumbers()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .foregroundStyle(HetzlyColors.textPrimary)
                        Image(systemName: didCopyIPv4 ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(HetzlyColors.textTertiary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("IPv4 address \(ipv4)")
                .accessibilityHint(didCopyIPv4 ? "Copied" : "Double tap to copy")
            }
            if let ipv6 = server.serverIPv6Net {
                Button(action: { copy(ipv6, isV4: false) }) {
                    HStack(spacing: Spacing.unit * 2) {
                        Text(ipv6)
                            .font(.system(size: 13, design: .monospaced))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .foregroundStyle(HetzlyColors.textSecondary)
                        Image(systemName: didCopyIPv6 ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(HetzlyColors.textTertiary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("IPv6 address \(ipv6)")
                .accessibilityHint(didCopyIPv6 ? "Copied" : "Double tap to copy")
            }
        }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.unit * 2) {
                GlassChip(server.product, systemImage: "cpu")
                GlassChip(server.dc, systemImage: "mappin.and.ellipse")
            }
        }
    }

    private func copy(_ value: String, isV4: Bool) {
        UIPasteboard.general.string = value
        copyHaptic.toggle()
        withAnimation(.snappy) {
            if isV4 { didCopyIPv4 = true } else { didCopyIPv6 = true }
        }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.snappy) {
                if isV4 { didCopyIPv4 = false } else { didCopyIPv6 = false }
            }
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        DedicatedServerHeroCard(server: DedicatedPreviewFixtures.server, onTapName: {})
            .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
