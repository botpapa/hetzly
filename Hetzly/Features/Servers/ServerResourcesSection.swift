import HetznerKit
import SwiftUI

/// RESOURCES section: quick-glance chips derived from the server model.
///
/// The binding `Server` contract (CONTRACTS.md) doesn't yet expose
/// `volumes`/`load_balancers` ID arrays, so this is placeholder-lite for
/// M1 as directed: chips built entirely from fields the contract does
/// guarantee (IP count, backups, rescue mode, delete/rebuild protection).
/// No navigation yet — swap in real volume/firewall counts and taps once
/// Worker A's model grows those fields.
struct ServerResourcesSection: View {
    let server: Server

    private var summary: ServerResourceSummary { ServerResourceSummary(server: server) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            SectionLabel("Resources")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.unit * 2) {
                    GlassChip("\(summary.ipCount) IP\(summary.ipCount == 1 ? "" : "s")", systemImage: "network")
                    GlassChip(summary.backupsEnabled ? "Backups On" : "Backups Off", systemImage: "clock.arrow.circlepath")
                    GlassChip(summary.rescueEnabled ? "Rescue On" : "Rescue Off", systemImage: "lifepreserver")
                    if summary.deleteProtected {
                        GlassChip("Delete Protected", systemImage: "lock.shield")
                    }
                    if summary.rebuildProtected {
                        GlassChip("Rebuild Protected", systemImage: "shield")
                    }
                }
            }
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        ServerResourcesSection(server: PreviewFixtures.server)
            .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
