import Foundation

/// Decoded response of `GET /servers/{id}/metrics`.
public struct ServerMetrics: Sendable, Equatable {
    public let start: Date
    public let end: Date
    public let step: TimeInterval
    public let series: [MetricsSeries]

    public init(start: Date, end: Date, step: TimeInterval, series: [MetricsSeries]) {
        self.start = start
        self.end = end
        self.step = step
        self.series = series
    }
}

/// One named metrics time series, e.g. `"cpu"` or `"network.0.bandwidth.in"`.
public struct MetricsSeries: Sendable {
    public let name: String
    public let points: [(timestamp: Date, value: Double)]

    public init(name: String, points: [(timestamp: Date, value: Double)]) {
        self.name = name
        self.points = points
    }
}

extension MetricsSeries: Equatable {
    // Tuple arrays aren't natively `Equatable`; compare element-wise instead
    // of relying on synthesis.
    public static func == (lhs: MetricsSeries, rhs: MetricsSeries) -> Bool {
        guard lhs.name == rhs.name, lhs.points.count == rhs.points.count else { return false }
        for (l, r) in zip(lhs.points, rhs.points) where l.timestamp != r.timestamp || l.value != r.value {
            return false
        }
        return true
    }
}

extension ServerMetrics: Decodable {
    private enum RootKeys: String, CodingKey { case metrics }
    private enum MetricsKeys: String, CodingKey {
        case start, end, step
        case timeSeries = "time_series"
    }

    public init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: RootKeys.self)
        let body = try root.nestedContainer(keyedBy: MetricsKeys.self, forKey: .metrics)

        start = try body.decode(Date.self, forKey: .start)
        end = try body.decode(Date.self, forKey: .end)
        step = try body.decode(TimeInterval.self, forKey: .step)

        let seriesContainer = try body.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .timeSeries)
        var decodedSeries: [MetricsSeries] = []
        for key in seriesContainer.allKeys {
            let raw = try seriesContainer.decode(RawMetricsSeries.self, forKey: key)
            decodedSeries.append(MetricsSeries(name: key.stringValue, points: raw.points))
        }
        // Deterministic order for callers/tests; the wire dictionary has none.
        series = decodedSeries.sorted { $0.name < $1.name }
    }
}

/// Decodes one `time_series` entry's `values` array: pairs of
/// `[unix_timestamp, "string-number"]`. Individual malformed pairs (bad
/// timestamp, non-numeric value, wrong arity, wrong shape entirely) are
/// skipped rather than failing the whole decode.
private struct RawMetricsSeries: Decodable {
    let points: [(timestamp: Date, value: Double)]

    private enum CodingKeys: String, CodingKey { case values }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rows = try container.decodeIfPresent([MetricsRow].self, forKey: .values) ?? []

        var parsed: [(timestamp: Date, value: Double)] = []
        for row in rows {
            guard row.scalars.count == 2, case .number(let timestamp) = row.scalars[0] else { continue }

            let value: Double?
            switch row.scalars[1] {
            case .number(let number): value = number
            case .string(let string): value = Double(string)
            case .other: value = nil
            }

            guard let value else { continue }
            parsed.append((timestamp: Date(timeIntervalSince1970: timestamp), value: value))
        }
        points = parsed
    }
}

/// One `[timestamp, value]` row, decoded permissively: never throws, even if
/// the row isn't an array at all — it just yields no scalars in that case.
private struct MetricsRow: Decodable {
    let scalars: [MetricsJSONScalar]

    init(from decoder: Decoder) throws {
        guard var container = try? decoder.unkeyedContainer() else {
            scalars = []
            return
        }
        var result: [MetricsJSONScalar] = []
        while !container.isAtEnd {
            let scalar = try container.decode(MetricsJSONScalar.self)
            result.append(scalar)
        }
        scalars = result
    }
}

/// A JSON scalar that never fails to decode — used so a single odd element
/// (unexpected null, nested object, etc.) can't abort the whole page.
private enum MetricsJSONScalar: Decodable {
    case number(Double)
    case string(String)
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            self = .other
        }
    }
}
