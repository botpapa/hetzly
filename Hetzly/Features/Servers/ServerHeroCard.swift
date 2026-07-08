import HetznerKit
import SwiftUI
import UIKit

/// The hero glass card at the top of Server Detail: status, name, IPs
/// (tap-to-copy), and a row of spec chips.
struct ServerHeroCard: View {
    let server: Server

    @State private var didCopyIPv4 = false
    @State private var didCopyIPv6 = false
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
                addressRow(
                    label: "IPv4",
                    address: ipv4,
                    font: .system(.body, design: .monospaced),
                    color: HetzlyColors.textPrimary,
                    isCopied: $didCopyIPv4
                )
            }
            // The wire value is a routed CIDR block (e.g. "2a01:...::/64"),
            // not a single host address — copied as-is, matching what the
            // hero already displays, since that's what a user pasting into
            // a DNS record or firewall rule actually wants.
            if let ipv6 = server.publicNet.ipv6?.ip {
                addressRow(
                    label: "IPv6",
                    address: ipv6,
                    font: .system(size: 13, design: .monospaced),
                    color: HetzlyColors.textSecondary,
                    isCopied: $didCopyIPv6
                )
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: copyHaptic)
    }

    /// One tap-to-copy address line, shared by the IPv4 and IPv6 rows:
    /// monospaced address text, a checkmark that swaps in for ~1.5s after a
    /// successful copy, and a light haptic on tap.
    private func addressRow(
        label: String, address: String, font: Font, color: Color, isCopied: Binding<Bool>
    ) -> some View {
        Button(action: { copy(address, isCopied: isCopied) }) {
            HStack(spacing: Spacing.unit * 2) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(HetzlyColors.textTertiary)
                    .frame(width: 34, alignment: .leading)
                Text(address)
                    .font(font)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(color)
                Image(systemName: isCopied.wrappedValue ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(HetzlyColors.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) address \(address)")
        .accessibilityHint(isCopied.wrappedValue ? "Copied" : "Double tap to copy")
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

    private func copy(_ value: String, isCopied: Binding<Bool>) {
        UIPasteboard.general.string = value
        copyHaptic.toggle()
        withAnimation(.snappy) { isCopied.wrappedValue = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.snappy) { isCopied.wrappedValue = false }
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

#Preview("Appearance: Light") {
    ZStack {
        CanvasBackground()
        ServerHeroCard(server: PreviewFixtures.server)
            .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.light)
}

#Preview("No IPv6") {
    ZStack {
        CanvasBackground()
        ServerHeroCard(server: PreviewFixtures.offServer)
            .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
