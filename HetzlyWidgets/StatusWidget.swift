import SwiftUI
import WidgetKit

/// Small home-screen + lock-screen widget: running/total server count, a
/// status dot (red when something needs attention, otherwise green), and a
/// relative "last synced" footer. No timeline polling — see
/// `SnapshotProvider`.
struct StatusWidget: Widget {
    let kind = "com.hetzly.app.widgets.status"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            StatusWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Status")
        .description("Running servers and anything that needs attention, at a glance.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}
