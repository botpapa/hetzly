import SwiftUI

/// The RESOURCES section of `ProjectDetailView`: a count-chip grid across
/// every non-server billable/manageable category for this project. Every
/// tile is purely informational — cross-tab navigation into the
/// project-scoped Resources lists (which read their own
/// `ResourcesProjectSelection`) is messy to wire from here, so tapping does
/// nothing and a footnote points the user at the Resources tab instead, per
/// the module contract's "keep honest and simple" guidance.
struct ProjectResourcesSection: View {
    let counts: ProjectDetailViewModel.ResourceCounts

    private struct Tile: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        let count: Int?
    }

    private var tiles: [Tile] {
        [
            Tile(id: "volumes", title: "Volumes", systemImage: "externaldrive", count: counts.volumes),
            Tile(id: "networks", title: "Networks", systemImage: "point.3.connected.trianglepath.dotted", count: counts.networks),
            Tile(id: "firewalls", title: "Firewalls", systemImage: "shield", count: counts.firewalls),
            Tile(id: "loadBalancers", title: "Load Balancers", systemImage: "arrow.left.arrow.right.circle", count: counts.loadBalancers),
            Tile(id: "primaryIPs", title: "Primary IPs", systemImage: "network", count: counts.primaryIPs),
            Tile(id: "floatingIPs", title: "Floating IPs", systemImage: "arrow.triangle.branch", count: counts.floatingIPs),
            Tile(id: "sshKeys", title: "SSH Keys", systemImage: "key", count: counts.sshKeys),
            Tile(id: "certificates", title: "Certificates", systemImage: "checkmark.seal", count: counts.certificates),
        ]
    }

    private let columns = [GridItem(.flexible(), spacing: Spacing.unit * 3), GridItem(.flexible(), spacing: Spacing.unit * 3)]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            SectionLabel("Resources")

            LazyVGrid(columns: columns, spacing: Spacing.unit * 3) {
                ForEach(tiles) { tile in
                    tileView(tile)
                }
            }

            Text("Manage in the Resources tab")
                .caption()
        }
    }

    private func tileView(_ tile: Tile) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                HStack {
                    Image(systemName: tile.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(HetzlyColors.accent)
                    Spacer()
                    Group {
                        if let count = tile.count {
                            Text("\(count)")
                        } else {
                            Text("—")
                        }
                    }
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(HetzlyColors.textPrimary)
                }
                Text(tile.title)
                    .bodySecondary()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tile.title): \(tile.count.map { "\($0)" } ?? "unavailable")")
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        ScrollView {
            ProjectResourcesSection(
                counts: ProjectDetailViewModel.ResourceCounts(
                    volumes: 3, networks: 1, firewalls: 2, loadBalancers: 0,
                    primaryIPs: 4, floatingIPs: 1, sshKeys: 5, certificates: nil
                )
            )
            .padding(Spacing.screenMargin)
        }
    }
    .preferredColorScheme(.dark)
}
