import HetznerKit
import SwiftUI

/// METRICS section: range picker + CPU / network / disk IO charts, sitting
/// directly on the canvas (no card background). Shows a redacted
/// placeholder while loading and a quiet caption when metrics can't be
/// loaded or come back empty.
struct ServerMetricsSection: View {
    let metrics: ServerMetrics?
    let state: ServerDetailViewModel.LoadState
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
        let cpu = MetricsSeriesLookup.points(named: ["cpu"], in: metrics)
        let netIn = MetricsSeriesLookup.points(named: ["network", "in"], in: metrics)
        let netOut = MetricsSeriesLookup.points(named: ["network", "out"], in: metrics)
        let diskRead = MetricsSeriesLookup.points(named: ["disk", "read"], in: metrics)
        let diskWrite = MetricsSeriesLookup.points(named: ["disk", "write"], in: metrics)

        ServerMetricsChart(
            title: "CPU",
            series: [MetricsChartSeries(name: "CPU", color: HetzlyColors.textPrimary, points: cpu)],
            showAreaFill: true,
            valueFormatter: { ServerDetailSupport.percent($0) },
            range: range
        )

        ServerMetricsChart(
            title: "Network",
            series: [
                MetricsChartSeries(name: "In", color: HetzlyColors.textPrimary, points: netIn),
                MetricsChartSeries(name: "Out", color: HetzlyColors.textSecondary, points: netOut),
            ],
            valueFormatter: { ServerDetailSupport.bytes($0, perSecond: true) },
            range: range
        )

        ServerMetricsChart(
            title: "Disk IO",
            series: [
                MetricsChartSeries(name: "Read", color: HetzlyColors.textPrimary, points: diskRead),
                MetricsChartSeries(name: "Write", color: HetzlyColors.textSecondary, points: diskWrite),
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
            ServerMetricsSection(metrics: PreviewFixtures.metrics, state: .loaded, range: $range)
                .padding(Spacing.screenMargin)
        }
    }
    .preferredColorScheme(.dark)
}
