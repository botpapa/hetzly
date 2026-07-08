import HetznerKit
import SwiftUI

/// METRICS section for a load balancer, directly reusing the Servers
/// feature's chart stack (`ServerMetricsChart`, `MetricsRangePicker`,
/// `MetricsSeriesLookup` — same app target): open connections,
/// connections/s, requests/s, and bandwidth in/out.
struct LBMetricsSection: View {
    let metrics: ServerMetrics?
    let state: LBDetailViewModel.LoadState
    @Binding var range: MetricsRange

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 6) {
            HStack {
                SectionLabel("Metrics")
                Spacer()
                MetricsRangePicker(selection: $range)
            }

            switch state {
            case .idle, .loading:
                loadingPlaceholder
            case .failed:
                emptyState
            case .loaded:
                if let metrics, !metrics.series.isEmpty {
                    charts(for: metrics)
                } else {
                    emptyState
                }
            }
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: Spacing.unit * 6) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 140)
            }
        }
        .redacted(reason: .placeholder)
    }

    private var emptyState: some View {
        Text("No metrics available")
            .caption()
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
    }

    // Chart colors are deliberately monochrome (`textPrimary`/`textSecondary`)
    // per CONTRACTS.md's accent-discipline rule: `HetzlyColors.accent` is
    // reserved for the primary CTA and running/status dots, not decorative
    // chart strokes. `HetzlyColors.accent` is reserved here for a future
    // threshold/attention state (e.g. a series crossing a configured alert
    // line) — none of these charts have that concept yet.
    @ViewBuilder
    private func charts(for metrics: ServerMetrics) -> some View {
        let openConnections = MetricsSeriesLookup.points(named: ["open_connections"], in: metrics)
        let connectionsPerSecond = MetricsSeriesLookup.points(named: ["connections_per_second"], in: metrics)
        let requestsPerSecond = MetricsSeriesLookup.points(named: ["requests_per_second"], in: metrics)
        let bandwidthIn = MetricsSeriesLookup.points(named: ["bandwidth", "in"], in: metrics)
        let bandwidthOut = MetricsSeriesLookup.points(named: ["bandwidth", "out"], in: metrics)

        ServerMetricsChart(
            title: "Open Connections",
            series: [MetricsChartSeries(name: "Open", color: HetzlyColors.textPrimary, points: openConnections)],
            showAreaFill: true,
            valueFormatter: { String(format: "%.0f", $0) },
            range: range
        )

        ServerMetricsChart(
            title: "Connections / s",
            series: [MetricsChartSeries(name: "Conn/s", color: HetzlyColors.textPrimary, points: connectionsPerSecond)],
            showAreaFill: true,
            valueFormatter: { String(format: "%.1f", $0) },
            range: range
        )

        ServerMetricsChart(
            title: "Requests / s",
            series: [MetricsChartSeries(name: "Req/s", color: HetzlyColors.textPrimary, points: requestsPerSecond)],
            showAreaFill: true,
            valueFormatter: { String(format: "%.1f", $0) },
            range: range
        )

        ServerMetricsChart(
            title: "Bandwidth",
            series: [
                MetricsChartSeries(name: "In", color: HetzlyColors.textPrimary, points: bandwidthIn),
                MetricsChartSeries(name: "Out", color: HetzlyColors.textSecondary, points: bandwidthOut),
            ],
            valueFormatter: { ServerDetailSupport.bytes($0, perSecond: true) },
            range: range
        )
    }
}

#Preview {
    @Previewable @State var range: MetricsRange = .oneHour
    return ScrollView {
        ZStack {
            CanvasBackground()
            LBMetricsSection(metrics: LBPreviewFixtures.metrics, state: .loaded, range: $range)
                .padding(Spacing.screenMargin)
        }
    }
    .preferredColorScheme(.dark)
}
