import Foundation
import HetznerKit

/// Formatting and derivation helpers shared across the Server Detail feature.
/// Kept free of view code so it stays trivially testable.
enum ServerDetailSupport {
    /// Formats a raw byte count as GB/TB (or smaller units for tiny values),
    /// e.g. `1.2 GB`. Pass `perSecond: true` for throughput readouts.
    static func bytes(_ value: Double, perSecond: Bool = false) -> String {
        let suffix = perSecond ? "/s" : ""
        let units: [(threshold: Double, unit: String)] = [
            (1e12, "TB"), (1e9, "GB"), (1e6, "MB"), (1e3, "KB"),
        ]
        for entry in units where value >= entry.threshold {
            return String(format: "%.1f %@%@", value / entry.threshold, entry.unit, suffix)
        }
        return String(format: "%.0f %@%@", value, perSecond ? "B" : "B", suffix)
    }

    /// Formats a 0–100 (or 0–1, auto-detected) value as a whole-number
    /// percentage, e.g. `42%`.
    static func percent(_ value: Double) -> String {
        let normalized = value <= 1 ? value * 100 : value
        return String(format: "%.0f%%", normalized)
    }

    /// Formats an image/disk size already expressed in GB, e.g. `12.4 GB`.
    /// (Distinct from `bytes(_:)`, which takes raw byte counts.)
    static func gigabytes(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f GB", value)
        }
        return String(format: "%.1f GB", value)
    }

    /// RFC 1123-style hostname validation for the server rename flow:
    /// dot-separated labels of letters/digits/hyphens, each 1–63 chars, no
    /// leading/trailing hyphen, 253 chars total.
    static func isValidHostname(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 253 else { return false }
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        for label in labels {
            guard !label.isEmpty, label.count <= 63 else { return false }
            guard !label.hasPrefix("-"), !label.hasSuffix("-") else { return false }
            guard label.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        }
        return true
    }

    /// Summarizes a server's billing-period traffic usage for the Control
    /// tab's Traffic row: outgoing/ingoing formatted via `bytes(_:)`, plus
    /// how far outgoing traffic is through the included quota (when Hetzner
    /// reported one). Returns `nil` when Hetzner hasn't reported ANY traffic
    /// yet (`outgoing`/`ingoing` both `nil` — e.g. a brand-new server), so
    /// the whole row can omit itself rather than showing a misleading "0 B".
    static func trafficUsage(outgoing: Int64?, ingoing: Int64?, included: Int64?) -> ServerTrafficUsage? {
        guard outgoing != nil || ingoing != nil else { return nil }
        let usageLine = "\(bytes(Double(outgoing ?? 0))) out · \(bytes(Double(ingoing ?? 0))) in"

        var includedLine: String?
        var fraction: Double?
        if let included, included > 0 {
            includedLine = "of \(bytes(Double(included))) included"
            fraction = Double(outgoing ?? 0) / Double(included)
        }

        return ServerTrafficUsage(
            usageLine: usageLine,
            includedLine: includedLine,
            fraction: fraction,
            percentText: fraction.map { String(format: "%.0f%%", $0 * 100) }
        )
    }

    /// "up 3 weeks" style uptime string, relative to `now`. Deliberately
    /// coarse — a single largest unit, matching the mascot-y, casual tone of
    /// the rest of the UI.
    static func uptime(since date: Date, now: Date = Date()) -> String {
        let interval = max(0, now.timeIntervalSince(date))
        let minute = 60.0
        let hour = minute * 60
        let day = hour * 24
        let week = day * 7
        let month = day * 30
        let year = day * 365

        let value: Int
        let unit: String
        if interval < hour {
            value = max(1, Int(interval / minute))
            unit = "minute"
        } else if interval < day {
            value = Int(interval / hour)
            unit = "hour"
        } else if interval < week {
            value = Int(interval / day)
            unit = "day"
        } else if interval < month {
            value = Int(interval / week)
            unit = "week"
        } else if interval < year {
            value = Int(interval / month)
            unit = "month"
        } else {
            value = Int(interval / year)
            unit = "year"
        }
        return "up \(value) \(unit)\(value == 1 ? "" : "s")"
    }
}

/// Regional-indicator flag emoji from an ISO 3166-1 alpha-2 country code.
/// Returns an empty string for malformed input rather than crashing.
enum CountryFlag {
    static func emoji(countryCode: String) -> String {
        let base: UInt32 = 127_397
        var scalars = String.UnicodeScalarView()
        for scalar in countryCode.uppercased().unicodeScalars {
            guard let flagScalar = Unicode.Scalar(base + scalar.value) else { return "" }
            scalars.append(flagScalar)
        }
        return String(scalars)
    }
}

extension ServerStatus {
    /// Maps the wire-level server status to the DesignSystem's coarse
    /// `ResourceStatus` used by `StatusDot`.
    var resourceStatus: ResourceStatus {
        switch self {
        case .running: .running
        case .off: .off
        case .initializing, .starting, .stopping, .deleting, .migrating, .rebuilding: .transitioning
        case .unknown: .unknown
        }
    }

    var displayName: String {
        switch self {
        case .running: "Running"
        case .off: "Off"
        case .initializing: "Initializing"
        case .starting: "Starting"
        case .stopping: "Stopping"
        case .deleting: "Deleting"
        case .migrating: "Migrating"
        case .rebuilding: "Rebuilding"
        case .unknown: "Unknown"
        }
    }
}

/// A single plotted sample, flattened out of `MetricsSeries.points` for use
/// directly as Swift Charts mark data.
struct ChartPoint: Identifiable, Sendable {
    let date: Date
    let value: Double
    var id: Date { date }
}

enum MetricsSeriesLookup {
    /// Finds series whose (lowercased) name contains every keyword, e.g.
    /// `["network", "in"]` matches Hetzner's `network.0.bandwidth.in`.
    static func series(named keywords: [String], in metrics: ServerMetrics) -> [MetricsSeries] {
        metrics.series.filter { entry in
            let lowered = entry.name.lowercased()
            return keywords.allSatisfy { lowered.contains($0) }
        }
    }

    /// Flattens every matching series' points into a single, time-sorted
    /// chart data array. Multiple matches (e.g. several disks) are summed
    /// per-timestamp when timestamps line up; otherwise simply concatenated.
    static func points(named keywords: [String], in metrics: ServerMetrics) -> [ChartPoint] {
        series(named: keywords, in: metrics)
            .flatMap { $0.points }
            .map { ChartPoint(date: $0.timestamp, value: $0.value) }
            .sorted { $0.date < $1.date }
    }
}

/// See `ServerDetailSupport.trafficUsage(outgoing:ingoing:included:)`.
struct ServerTrafficUsage: Sendable, Equatable {
    /// e.g. `"1.2 TB out · 340 GB in"`.
    let usageLine: String
    /// e.g. `"of 20 TB included"` — `nil` when Hetzner didn't report an
    /// included quota for this server.
    let includedLine: String?
    /// Outgoing ÷ included, only when both are known and `included > 0`.
    /// Can exceed `1.0` — billed overage is a real, expected state worth
    /// showing clearly, not clamping away.
    let fraction: Double?
    /// `fraction` formatted as a whole-number percentage, e.g. `"34%"` or
    /// `"154%"`. Computed independently of `ServerDetailSupport.percent(_:)`
    /// since that helper auto-detects 0–1 vs. 0–100 input and would
    /// misread an over-100%-as-fraction value like `1.54`.
    let percentText: String?
}

/// Everything the Resources section can show using only fields guaranteed
/// by the binding `Server` model contract (no `volumes`/`load_balancers`
/// arrays are specified there yet — see worker report for the deviation).
struct ServerResourceSummary: Sendable {
    let ipCount: Int
    let backupsEnabled: Bool
    let rescueEnabled: Bool
    let deleteProtected: Bool
    let rebuildProtected: Bool

    init(server: Server) {
        var ips = 0
        if server.publicNet.ipv4 != nil { ips += 1 }
        if server.publicNet.ipv6 != nil { ips += 1 }
        ipCount = ips
        backupsEnabled = server.backupWindow != nil
        rescueEnabled = server.rescueEnabled
        deleteProtected = server.protection.delete
        rebuildProtected = server.protection.rebuild
    }
}
