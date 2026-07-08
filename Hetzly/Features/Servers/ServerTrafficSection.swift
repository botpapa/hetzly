import HetznerKit
import SwiftUI

/// TRAFFIC row on the Control tab: this billing period's outgoing/ingoing
/// usage against the server's included quota, with a thin usage bar
/// (outgoing vs. included). Omits itself entirely when Hetzner hasn't
/// reported any traffic yet — see
/// `ServerDetailSupport.trafficUsage(outgoing:ingoing:included:)`.
struct ServerTrafficSection: View {
    let server: Server

    private var usage: ServerTrafficUsage? {
        ServerDetailSupport.trafficUsage(
            outgoing: server.outgoingTraffic,
            ingoing: server.ingoingTraffic,
            included: server.includedTraffic
        )
    }

    var body: some View {
        if let usage {
            VStack(alignment: .leading, spacing: Spacing.unit * 4) {
                SectionLabel("Traffic")

                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(usage.usageLine)
                                .hetzlyMonoNumbers()
                                .foregroundStyle(HetzlyColors.textPrimary)
                            Spacer()
                            if let percentText = usage.percentText {
                                Text(percentText)
                                    .font(.system(size: 13, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundStyle(barColor(for: usage.fraction ?? 0))
                            }
                        }

                        if let fraction = usage.fraction {
                            usageBar(fraction: fraction)
                        }

                        if let includedLine = usage.includedLine {
                            Text(includedLine)
                                .caption()
                        }

                        if let fraction = usage.fraction, fraction > 1 {
                            Text("Over included traffic — extra usage is billed by Hetzner.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(HetzlyColors.destructive)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    /// Neutral until ~90% of the included quota, accent from there to
    /// signal "getting close", and the destructive color past 100% since
    /// that's real, billed overage rather than just a warning.
    private func usageBar(fraction: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(HetzlyColors.textTertiary.opacity(0.2))
                Capsule()
                    .fill(barColor(for: fraction))
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 4)
    }

    private func barColor(for fraction: Double) -> Color {
        if fraction > 1 { return HetzlyColors.destructive }
        if fraction >= 0.9 { return HetzlyColors.accent }
        return HetzlyColors.textTertiary
    }
}

#Preview("Under quota") {
    ZStack {
        CanvasBackground()
        ServerTrafficSection(server: PreviewFixtures.server)
            .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}

#Preview("Over quota") {
    ZStack {
        CanvasBackground()
        ServerTrafficSection(server: PreviewFixtures.serverOverTrafficQuota)
            .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}

#Preview("No traffic reported yet") {
    ZStack {
        CanvasBackground()
        ServerTrafficSection(server: PreviewFixtures.serverWithoutTrafficData)
            .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
