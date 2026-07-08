import HetznerKit
import SwiftUI

/// REVERSE DNS section: one row per IP on this server (filtered client-side
/// from the account-wide `listIPs()`), each with its current PTR record (or
/// "Hetzner default") and an edit entry point.
struct DedicatedRDNSSection: View {
    let ips: [RobotIP]
    let rdnsByIP: [String: String]
    let ipsState: DedicatedServerDetailViewModel.LoadState
    var onEdit: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            SectionLabel("Reverse DNS")

            GlassCard {
                switch ipsState {
                case .idle, .loading:
                    HStack(spacing: Spacing.unit * 2) {
                        ProgressView()
                        Text("Loading IPs…").caption()
                    }
                case .failed(let message):
                    Text(message).caption()
                case .loaded:
                    if ips.isEmpty {
                        Text("No IPs found for this server.").bodySecondary()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(ips.enumerated()), id: \.element.ip) { index, ip in
                                if index > 0 {
                                    Divider().overlay(HetzlyColors.textTertiary.opacity(0.2))
                                }
                                rdnsRow(ip)
                            }
                        }
                    }
                }
            }
        }
    }

    private func rdnsRow(_ ip: RobotIP) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.unit) {
                Text(ip.ip)
                    .hetzlyMonoNumbers()
                    .foregroundStyle(HetzlyColors.textPrimary)
                Text(rdnsByIP[ip.ip] ?? "Hetzner default")
                    .caption()
            }
            Spacer()
            Button("Edit") { onEdit(ip.ip) }
                .secondaryCTAStyle()
        }
        .padding(.vertical, Spacing.unit * 2)
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        DedicatedRDNSSection(
            ips: [DedicatedPreviewFixtures.ip],
            rdnsByIP: [DedicatedPreviewFixtures.ip.ip: "host.example.com"],
            ipsState: .loaded,
            onEdit: { _ in }
        )
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
