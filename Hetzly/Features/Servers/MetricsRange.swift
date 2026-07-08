import Foundation

/// Selectable lookback window for the metrics charts, backing the glass
/// segmented capsule picker.
enum MetricsRange: String, CaseIterable, Identifiable, Sendable {
    case oneHour
    case oneDay
    case sevenDays
    case thirtyDays

    var id: String { rawValue }

    var label: String {
        switch self {
        case .oneHour: "1H"
        case .oneDay: "24H"
        case .sevenDays: "7D"
        case .thirtyDays: "30D"
        }
    }

    /// Total lookback window, ending now.
    var duration: TimeInterval {
        switch self {
        case .oneHour: 3_600
        case .oneDay: 86_400
        case .sevenDays: 7 * 86_400
        case .thirtyDays: 30 * 86_400
        }
    }

    /// Sample step passed to `CloudClient.serverMetrics`. Hetzner caps the
    /// number of samples returned, so wider windows use a coarser step.
    var step: TimeInterval {
        switch self {
        case .oneHour: 60
        case .oneDay: 300
        case .sevenDays: 1_800
        case .thirtyDays: 7_200
        }
    }

    /// Formats a timestamp for the scrub lollipop, appropriate to the
    /// window's granularity.
    func timeLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        switch self {
        case .oneHour, .oneDay:
            formatter.dateFormat = "HH:mm"
        case .sevenDays, .thirtyDays:
            formatter.dateFormat = "MMM d, HH:mm"
        }
        return formatter.string(from: date)
    }
}
