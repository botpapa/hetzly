import Foundation

/// Sample data for the widget gallery / Xcode previews. `WidgetSnapshot`
/// itself is defined in `Shared/` (compiled into both targets), but this
/// fixture is widget-UI-only, so it lives here instead.
extension WidgetSnapshot {
    static let placeholder = WidgetSnapshot(
        updatedAt: Date(),
        totalServers: 4,
        runningServers: 3,
        attentionCount: 1,
        monthToDate: "€18.42",
        projected: "€42.90",
        topServers: [
            ServerSummary(name: "web-01", statusRaw: "running", cpuSamples: [12, 20, 18, 34, 40, 30, 22]),
            ServerSummary(name: "db-01", statusRaw: "running", cpuSamples: [5, 8, 6, 9, 12, 10, 7]),
            ServerSummary(name: "worker-03", statusRaw: "stopping", cpuSamples: [2, 3, 2, 4, 3, 5, 4]),
        ]
    )
}
