import Charts
import SwiftUI

/// One plotted series in a `ServerMetricsChart` (e.g. "In"/"Out" for the
/// network chart, or a single "CPU" series with an area-fill gradient).
struct MetricsChartSeries: Identifiable {
    let id = UUID()
    let name: String
    let color: Color
    let points: [ChartPoint]
}

/// A single metrics chart: LineMark (+ optional AreaMark gradient fade for
/// single-series charts), sitting directly on the canvas — no card
/// background. Gridlines are suppressed except a hairline bottom rule and a
/// minimal 2-mark Y axis. Drag to scrub: a vertical hairline plus a glass
/// lollipop chip showing the nearest value and time.
struct ServerMetricsChart: View {
    let title: String
    let series: [MetricsChartSeries]
    var showAreaFill: Bool = false
    let valueFormatter: (Double) -> String
    let range: MetricsRange

    @State private var scrubDate: Date?

    private var hasData: Bool {
        series.contains { !$0.points.isEmpty }
    }

    /// A spoken summary of the chart's most recent value(s), read by
    /// VoiceOver instead of trying to traverse individual chart marks —
    /// e.g. "latest 42%" for a single-series chart, or "In 1.2 MB/s, Out
    /// 340 KB/s" when there's more than one series.
    private var chartAccessibilitySummary: String {
        let summaries = series.compactMap { entry -> String? in
            guard let latest = entry.points.last else { return nil }
            return series.count > 1
                ? "\(entry.name) \(valueFormatter(latest.value))"
                : "latest \(valueFormatter(latest.value))"
        }
        return summaries.isEmpty ? "No data" : summaries.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(HetzlyColors.textTertiary)
                Spacer()
                if series.count > 1 {
                    legend
                }
            }

            if hasData {
                chart
                    .frame(height: 140)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(HetzlyColors.textTertiary.opacity(0.25))
                            .frame(height: 1)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(title) chart")
                    .accessibilityValue(chartAccessibilitySummary)
            } else {
                Text("No metrics available")
                    .caption()
                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: Spacing.unit * 3) {
            ForEach(series) { entry in
                HStack(spacing: Spacing.unit) {
                    Circle().fill(entry.color).frame(width: 6, height: 6)
                    Text(entry.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(HetzlyColors.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        Chart {
            ForEach(series) { entry in
                ForEach(entry.points) { point in
                    // `series:` is load-bearing on multi-series charts:
                    // without it, Charts treats every LineMark as one
                    // series and connects In→Out (Read→Write) into a
                    // single path, drawing a stray arc across the plot.
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value(entry.name, point.value),
                        series: .value("Series", entry.name)
                    )
                    .foregroundStyle(entry.color)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))

                    if showAreaFill && series.count == 1 {
                        AreaMark(
                            x: .value("Time", point.date),
                            y: .value(entry.name, point.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [entry.color.opacity(0.35), entry.color.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
            }

            if let scrubDate {
                RuleMark(x: .value("Time", scrubDate))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(HetzlyColors.textTertiary.opacity(0.6))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 2)) { _ in
                AxisValueLabel()
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(scrubGesture(proxy: proxy, geometry: geometry))

                    if let scrubDate, let nearest = nearestPoint(to: scrubDate),
                       let x = proxy.position(forX: nearest.date), let plotFrame = proxy.plotFrame {
                        let plotOrigin = geometry[plotFrame].origin
                        GlassChip("\(valueFormatter(nearest.value)) · \(range.timeLabel(for: nearest.date))")
                            .fixedSize()
                            .offset(x: lollipopOffset(x: plotOrigin.x + x, containerWidth: geometry.size.width), y: 0)
                    }
                }
            }
        }
    }

    private func scrubGesture(proxy: ChartProxy, geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let plotFrame = proxy.plotFrame else { return }
                let originX = geometry[plotFrame].origin.x
                let relativeX = value.location.x - originX
                guard let date = proxy.value(atX: relativeX, as: Date.self) else { return }
                scrubDate = date
            }
            .onEnded { _ in
                withAnimation(.snappy) { scrubDate = nil }
            }
    }

    private func nearestPoint(to date: Date) -> ChartPoint? {
        series.flatMap(\.points).min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }
    }

    /// Keeps the lollipop chip from overflowing the chart's leading/trailing
    /// edge by clamping its offset.
    private func lollipopOffset(x: CGFloat, containerWidth: CGFloat) -> CGFloat {
        let chipWidth: CGFloat = 120
        return min(max(0, x - chipWidth / 2), max(0, containerWidth - chipWidth))
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        VStack(alignment: .leading, spacing: Spacing.unit * 6) {
            ServerMetricsChart(
                title: "CPU",
                series: [
                    MetricsChartSeries(
                        name: "CPU",
                        color: HetzlyColors.accent,
                        points: PreviewFixtures.metrics.series[0].points.map {
                            ChartPoint(date: $0.timestamp, value: $0.value)
                        }
                    ),
                ],
                showAreaFill: true,
                valueFormatter: { ServerDetailSupport.percent($0) },
                range: .oneHour
            )

            ServerMetricsChart(
                title: "Network",
                series: [
                    MetricsChartSeries(
                        name: "In",
                        color: HetzlyColors.accent,
                        points: PreviewFixtures.metrics.series[1].points.map {
                            ChartPoint(date: $0.timestamp, value: $0.value)
                        }
                    ),
                    MetricsChartSeries(
                        name: "Out",
                        color: HetzlyColors.textSecondary,
                        points: PreviewFixtures.metrics.series[2].points.map {
                            ChartPoint(date: $0.timestamp, value: $0.value)
                        }
                    ),
                ],
                valueFormatter: { ServerDetailSupport.bytes($0, perSecond: true) },
                range: .oneHour
            )

            ServerMetricsChart(
                title: "Disk IO",
                series: [],
                valueFormatter: { ServerDetailSupport.bytes($0, perSecond: true) },
                range: .oneHour
            )
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
