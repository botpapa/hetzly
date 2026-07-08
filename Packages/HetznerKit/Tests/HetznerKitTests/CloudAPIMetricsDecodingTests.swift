import Foundation
import Testing
@testable import HetznerKit

@Suite("CloudAPI metrics decoding")
struct CloudAPIMetricsDecodingTests {
    private let decoder = makeHetznerJSONDecoder()

    @Test func decodesSeriesAndSkipsMalformedPairs() throws {
        let metrics = try decoder.decode(ServerMetrics.self, from: CloudAPIFixtures.metricsJSON)

        #expect(metrics.step == 60)
        #expect(metrics.series.count == 2)

        let cpu = try #require(metrics.series.first { $0.name == "cpu" })
        // 4 raw rows in the fixture, 2 malformed (non-numeric value,
        // non-numeric timestamp) — only the 2 well-formed rows should survive.
        #expect(cpu.points.count == 2)
        #expect(cpu.points[0].value == 42.5)
        #expect(cpu.points[1].value == 55)

        let network = try #require(metrics.series.first { $0.name == "network.0.bandwidth.in" })
        #expect(network.points.count == 1)
        #expect(network.points[0].value == 100)
    }

    @Test func startAndEndDatesDecode() throws {
        let metrics = try decoder.decode(ServerMetrics.self, from: CloudAPIFixtures.metricsJSON)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        #expect(metrics.start == formatter.date(from: "2016-01-30T23:50:00Z"))
        #expect(metrics.end == formatter.date(from: "2016-01-30T23:55:00Z"))
    }

    @Test func emptySeriesDictionaryDecodesToEmptyArray() throws {
        let json = Data(
            """
            {"metrics": {"start": "2016-01-30T23:50:00Z", "end": "2016-01-30T23:55:00Z", "step": 60, "time_series": {}}}
            """.utf8
        )
        let metrics = try decoder.decode(ServerMetrics.self, from: json)
        #expect(metrics.series.isEmpty)
    }
}
