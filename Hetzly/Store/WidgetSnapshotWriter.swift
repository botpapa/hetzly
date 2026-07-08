import Foundation
import HetznerKit
import WidgetKit

/// Bridges `DashboardViewModel` state into the App Group container so
/// `HetzlyWidgets` can render without a token, an IP address, or a network
/// call of its own. Write-only from the app's side — the widget extension
/// only ever reads `WidgetSnapshotIO.load()`.
enum WidgetSnapshotWriter {
    /// Builds a `WidgetSnapshot` from the dashboard's current in-memory
    /// state and writes it to the shared container, then asks WidgetKit to
    /// reload every installed Hetzly widget. Safe to call as often as a
    /// load/refresh completes — the file write is atomic and cheap, and
    /// `WidgetCenter` coalesces reloads internally.
    static func write(
        projectSections: [DashboardViewModel.ProjectSection],
        cpuSparklines: [String: [Double]],
        monthToDate: Decimal?,
        projected: Decimal?,
        currency: String
    ) {
        let allServers = projectSections.flatMap(\.servers)
        let runningCount = allServers.filter { $0.status == .running }.count
        let attentionCount = allServers.filter { isAttentionStatus($0.status) }.count

        let snapshot = WidgetSnapshot(
            updatedAt: Date(),
            totalServers: allServers.count,
            runningServers: runningCount,
            attentionCount: attentionCount,
            monthToDate: monthToDate.map { CurrencyFormat.string($0, currencyCode: currency) },
            projected: projected.map { CurrencyFormat.string($0, currencyCode: currency) },
            topServers: topServers(from: allServers, cpuSparklines: cpuSparklines)
        )

        guard WidgetSnapshotIO.save(snapshot) else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Ranks by average CPU when at least one server has sparkline data;
    /// otherwise falls back to the first 3 servers in list order, so the
    /// widget still shows *something* before the lazy CPU fetch completes.
    private static func topServers(
        from servers: [ServerListItem],
        cpuSparklines: [String: [Double]]
    ) -> [WidgetSnapshot.ServerSummary] {
        let hasCPUData = servers.contains { cpuSparklines[$0.id] != nil }

        let ranked: [ServerListItem]
        if hasCPUData {
            ranked = servers.sorted { averageCPU(cpuSparklines[$0.id]) > averageCPU(cpuSparklines[$1.id]) }
        } else {
            ranked = servers
        }

        return ranked.prefix(3).map { item in
            WidgetSnapshot.ServerSummary(
                name: item.name,
                statusRaw: item.status.rawValue,
                cpuSamples: cpuSparklines[item.id] ?? []
            )
        }
    }

    private static func averageCPU(_ samples: [Double]?) -> Double {
        guard let samples, !samples.isEmpty else { return -1 }
        return samples.reduce(0, +) / Double(samples.count)
    }
}
