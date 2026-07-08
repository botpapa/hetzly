import SwiftUI
import WidgetKit

/// Renders the "Top servers" medium widget: up to 3 rows, each a status
/// dot, the server name, and a tiny CPU sparkline.
struct TopServersWidgetEntryView: View {
    let entry: SnapshotEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, !snapshot.topServers.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("TOP SERVERS")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(WidgetColors.textTertiary)

                    ForEach(Array(snapshot.topServers.prefix(3).enumerated()), id: \.offset) { _, server in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(WidgetColors.statusColor(forRaw: server.statusRaw))
                                .frame(width: 8, height: 8)
                            Text(server.name)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(WidgetColors.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            WidgetSparklineView(values: server.cpuSamples)
                        }
                    }

                    Spacer(minLength: 0)
                }
            } else {
                EmptyStateView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .containerBackground(for: .widget) { WidgetColors.canvas }
    }
}

#Preview {
    TopServersWidgetEntryView(entry: SnapshotEntry(date: .now, snapshot: .placeholder))
        .frame(width: 329, height: 155)
        .preferredColorScheme(.dark)
}

#Preview("Empty") {
    TopServersWidgetEntryView(entry: SnapshotEntry(date: .now, snapshot: nil))
        .frame(width: 329, height: 155)
        .preferredColorScheme(.dark)
}
