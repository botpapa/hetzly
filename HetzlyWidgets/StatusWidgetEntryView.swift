import SwiftUI
import WidgetKit

/// Renders the "Status" widget for both families it supports:
/// `.systemSmall` (home screen) and `.accessoryCircular` (lock screen).
struct StatusWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: SnapshotEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circularBody
            default:
                smallBody
            }
        }
        .containerBackground(for: .widget) {
            family == .accessoryCircular ? Color.clear : WidgetColors.canvas
        }
    }

    @ViewBuilder
    private var smallBody: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(snapshot.attentionCount > 0 ? WidgetColors.statusError : WidgetColors.statusRunning)
                        .frame(width: 8, height: 8)
                    if snapshot.attentionCount > 0 {
                        Text("\(snapshot.attentionCount) needs attention")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(WidgetColors.statusError)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)

                Text("\(snapshot.runningServers)/\(snapshot.totalServers)")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(WidgetColors.textPrimary)
                Text("running")
                    .font(.caption2)
                    .foregroundStyle(WidgetColors.textSecondary)

                Spacer(minLength: 0)

                HStack {
                    Text("Hetzly")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WidgetColors.textTertiary)
                    Spacer(minLength: 0)
                    Text(snapshot.updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(WidgetColors.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        } else {
            EmptyStateView()
        }
    }

    @ViewBuilder
    private var circularBody: some View {
        if let snapshot = entry.snapshot {
            Gauge(
                value: Double(snapshot.runningServers),
                in: 0...Double(max(snapshot.totalServers, 1))
            ) {
                Text("Hetzly")
            } currentValueLabel: {
                Text("\(snapshot.runningServers)")
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
            .tint(snapshot.attentionCount > 0 ? WidgetColors.statusError : WidgetColors.statusRunning)
        } else {
            EmptyStateView(compact: true)
        }
    }
}

#Preview {
    StatusWidgetEntryView(entry: SnapshotEntry(date: .now, snapshot: .placeholder))
        .frame(width: 155, height: 155)
        .preferredColorScheme(.dark)
}

#Preview("Empty") {
    StatusWidgetEntryView(entry: SnapshotEntry(date: .now, snapshot: nil))
        .frame(width: 155, height: 155)
        .preferredColorScheme(.dark)
}
