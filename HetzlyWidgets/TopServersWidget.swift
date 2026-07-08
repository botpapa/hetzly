import SwiftUI
import WidgetKit

/// Medium home-screen widget listing the busiest (or first 3, if CPU data
/// hasn't loaded yet) servers across every project, with a tiny sparkline
/// per row.
struct TopServersWidget: Widget {
    let kind = "com.hetzly.app.widgets.topServers"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            TopServersWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Top Servers")
        .description("Your busiest servers and their recent CPU activity.")
        .supportedFamilies([.systemMedium])
    }
}
