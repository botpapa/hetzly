import SwiftUI

/// A single server's row on the dashboard: status, name, type, location, and
/// an optional tiny CPU sparkline. Kept as a plain presentation view — its
/// parent wraps it in a `NavigationLink(value: ServerRoute(...))`.
struct ServerRowView: View {
    let item: ServerListItem
    let cpuSamples: [Double]?

    var body: some View {
        GlassCard(interactive: true) {
            HStack(spacing: Spacing.unit * 3) {
                StatusDot(resourceStatus(for: item.status))

                VStack(alignment: .leading, spacing: Spacing.unit) {
                    Text(item.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(HetzlyColors.textPrimary)

                    HStack(spacing: Spacing.unit * 2) {
                        GlassChip(item.typeName)
                        Text("\(flagEmoji(countryCode: item.countryCode)) \(item.city)")
                            .bodySecondary()
                    }
                }

                Spacer(minLength: Spacing.unit * 2)

                if let cpuSamples, cpuSamples.count > 1 {
                    CPUSparklineView(values: cpuSamples)
                }
            }
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        VStack(spacing: Spacing.unit * 3) {
            ServerRowView(
                item: ServerListItem(
                    projectID: UUID(),
                    serverID: 1,
                    name: "web-01",
                    status: .running,
                    typeName: "cx22",
                    city: "Falkenstein",
                    countryCode: "DE"
                ),
                cpuSamples: [12, 20, 18, 34, 40, 30, 22]
            )
            ServerRowView(
                item: ServerListItem(
                    projectID: UUID(),
                    serverID: 2,
                    name: "worker-03",
                    status: .stopping,
                    typeName: "cx22",
                    city: "Ashburn",
                    countryCode: "US"
                ),
                cpuSamples: nil
            )
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
