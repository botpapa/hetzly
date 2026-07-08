import HetznerKit
import SwiftUI
import UIKit

/// The hero glass card at the top of Server Detail: status, name, IPs
/// (tap-to-copy), and a row of spec chips.
struct ServerHeroCard: View {
    let server: Server

    @State private var didCopyIPv4 = false
    @State private var copyHaptic = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 4) {
                HStack(spacing: Spacing.unit * 2) {
                    StatusDot(server.status.resourceStatus)
                    Text(server.status.displayName)
                        .bodySecondary()
                    Spacer()
                    if server.status == .running {
                        Text(ServerDetailSupport.uptime(since: server.created))
                            .caption()
                    }
                }

                Text(server.name)
                    .font(.system(size: 22, weight: .bold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .foregroundStyle(HetzlyColors.textPrimary)

                addressBlock

                chipRow
            }
        }
    }

    @ViewBuilder
    private var addressBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.unit) {
            if let ipv4 = server.publicNet.ipv4?.ip {
                Button(action: { copy(ipv4) }) {
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
            if let ipv6 = server.publicNet.ipv6?.ip {
                Text(ipv6)
                    .hetzlyMonoNumbers()
                    .font(.system(size: 13, design: .monospaced))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(HetzlyColors.textSecondary)
                    .accessibilityLabel("IPv6 address \(ipv6)")
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: copyHaptic)
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.unit * 2) {
                GlassChip(server.serverType.name, systemImage: "cpu")
                GlassChip(specsLabel, systemImage: "memorychip")
                GlassChip(datacenterLabel, systemImage: "mappin.and.ellipse")
            }
        }
    }

    private var specsLabel: String {
        let cores = server.serverType.cores
        let ram = server.serverType.memory
        let disk = server.primaryDiskSize
        let ramString = ram.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", ram)
            : String(format: "%.1f", ram)
        return "\(cores) vCPU · \(ramString) GB · \(disk) GB"
    }

    private var datacenterLabel: String {
        let flag = CountryFlag.emoji(countryCode: server.datacenter.location.country)
        return "\(flag) \(server.datacenter.location.city)"
    }

    private func copy(_ value: String) {
        UIPasteboard.general.string = value
        copyHaptic.toggle()
        withAnimation(.snappy) { didCopyIPv4 = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.snappy) { didCopyIPv4 = false }
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        ServerHeroCard(server: PreviewFixtures.server)
            .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
