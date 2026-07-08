import Charts
import SwiftUI
import XCTest
@testable import Hetzly

/// Regression coverage for the multi-series chart path: without an explicit
/// `series:` value on `LineMark`, Swift Charts joins the two series into one
/// connected path, drawing a stray arc from the end of "In" back to the
/// start of "Out". A pure render-success check can't see that, so this test
/// also counts colored pixels in the plot's upper region — the stray arc
/// sweeps through otherwise-empty space above both real lines, so a
/// correctly-split chart has a mostly-empty upper band while the bug fills
/// it with a long stroke.
@MainActor
final class MetricsChartRenderTests: XCTestCase {
    private func twoSeriesChart() -> ServerMetricsChart {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        // "In" is a flat LOW line; "Out" is a flat HIGH line drawn after it.
        // With the series bug, the join stroke crosses the vertical gap
        // between them across the whole plot; correctly split, the band
        // strictly between the two flat lines stays empty.
        let low: [ChartPoint] = (0..<60).map {
            ChartPoint(date: start.addingTimeInterval(Double($0) * 60), value: 10)
        }
        let high: [ChartPoint] = (0..<60).map {
            ChartPoint(date: start.addingTimeInterval(Double($0) * 60), value: 100)
        }
        return ServerMetricsChart(
            title: "Network",
            series: [
                MetricsChartSeries(name: "In", color: HetzlyColors.accent, points: low),
                MetricsChartSeries(name: "Out", color: HetzlyColors.textSecondary, points: high),
            ],
            valueFormatter: { String(Int($0)) },
            range: .oneHour,
            // ImageRenderer can't rasterize the UIKit scrub overlay (it
            // draws a full-size placeholder over the chart) — render tests
            // exercise the drawing, not the gesture.
            interactive: false
        )
    }

    func test_twoSeriesChart_doesNotJoinSeriesIntoOnePath() throws {
        let size = CGSize(width: 360, height: 180)
        let image = try XCTUnwrap(
            RenderTestSupport.renderCGImage(
                twoSeriesChart().background(HetzlyColors.canvas),
                size: size
            )
        )

        // Debug escape hatch: export the render for human inspection when
        // the env var is set (simulator processes can write host paths).
        if let exportPath = ProcessInfo.processInfo.environment["HETZLY_CHART_EXPORT"] {
            let uiImage = UIImage(cgImage: image)
            try? uiImage.pngData()?.write(to: URL(fileURLWithPath: exportPath))
        }

        // Sample the horizontal band midway between the two flat lines
        // (roughly 40–60% of plot height). With split series it contains
        // only background; with the join bug the connecting stroke passes
        // through it. Tolerate a little antialiasing noise.
        var litPixels = 0
        let yRange = Int(Double(image.height) * 0.45)...Int(Double(image.height) * 0.60)
        for x in stride(from: 10, to: image.width - 10, by: 6) {
            for y in stride(from: yRange.lowerBound, to: yRange.upperBound, by: 4) {
                if let px = RenderTestSupport.pixel(of: image, x: x, y: y),
                   px.a > 200, Int(px.r) + Int(px.g) + Int(px.b) > 90 {
                    litPixels += 1
                }
            }
        }

        XCTAssertLessThan(
            litPixels, 12,
            "Mid-band between the two series contains \(litPixels) lit pixels — "
                + "a stray series-joining stroke is likely being drawn."
        )

        // Sanity: both real lines actually rendered (their own bands are lit).
        var highBandLit = 0
        for x in stride(from: 10, to: image.width - 10, by: 6) {
            for y in stride(from: Int(Double(image.height) * 0.10), to: Int(Double(image.height) * 0.38), by: 2) {
                if let px = RenderTestSupport.pixel(of: image, x: x, y: y),
                   px.a > 200, Int(px.r) + Int(px.g) + Int(px.b) > 90 {
                    highBandLit += 1
                }
            }
        }
        XCTAssertGreaterThan(highBandLit, 10, "The high ('Out') series never rendered.")
    }
}
