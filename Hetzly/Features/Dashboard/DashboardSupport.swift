import HetznerKit
import SwiftUI

/// Maps a `HetznerKit.ServerStatus` (the full Hetzner lifecycle enum) down to
/// the coarse `ResourceStatus` the design system's `StatusDot` understands.
func resourceStatus(for status: ServerStatus) -> ResourceStatus {
    switch status {
    case .running:
        return .running
    case .off:
        return .off
    case .initializing, .starting, .stopping, .deleting, .migrating, .rebuilding:
        return .transitioning
    case .unknown:
        return .unknown
    }
}

/// A server needs attention on the dashboard whenever it isn't settled into
/// a steady `.running` or `.off` state — i.e. anything mid-transition
/// (starting, stopping, migrating, rebuilding, deleting, initializing) or in
/// an unrecognized/unknown state.
func isAttentionStatus(_ status: ServerStatus) -> Bool {
    let resolved = resourceStatus(for: status)
    return resolved != .running && resolved != .off
}

/// Builds a regional-indicator flag emoji from an ISO 3166-1 alpha-2 country
/// code (e.g. "DE" -> "🇩🇪"). Falls back to a white flag for anything that
/// isn't a clean two-letter alphabetic code.
func flagEmoji(countryCode: String) -> String {
    let normalized = countryCode.uppercased()
    let fallback = "🏳️"

    guard normalized.unicodeScalars.count == 2,
          normalized.unicodeScalars.allSatisfy({ $0.isASCII && $0.properties.isAlphabetic })
    else {
        return fallback
    }

    let regionalIndicatorBase: UInt32 = 0x1F1E6 // Regional Indicator Symbol Letter A
    let letterABase = Unicode.Scalar("A").value

    var flag = ""
    for scalar in normalized.unicodeScalars {
        guard let indicator = Unicode.Scalar(regionalIndicatorBase + (scalar.value - letterABase)) else {
            return fallback
        }
        flag.unicodeScalars.append(indicator)
    }
    return flag
}

/// A minimal line-only sparkline path: no axes, no fill, values normalized
/// to the shape's bounding rect.
struct SparklineShape: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }

        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let range = maxValue - minValue
        let stepX = rect.width / CGFloat(values.count - 1)

        for (index, value) in values.enumerated() {
            let x = CGFloat(index) * stepX
            let normalized = range > 0 ? (value - minValue) / range : 0.5
            let y = rect.height - (CGFloat(normalized) * rect.height)
            let point = CGPoint(x: x, y: y)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

/// Small, fixed-size CPU sparkline used in server rows: 40×16, tertiary text
/// color, no axes.
struct CPUSparklineView: View {
    let values: [Double]

    var body: some View {
        SparklineShape(values: values)
            .stroke(HetzlyColors.textTertiary, lineWidth: 1.5)
            .frame(width: 40, height: 16)
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        VStack(spacing: Spacing.unit * 4) {
            CPUSparklineView(values: [12, 18, 15, 40, 55, 30, 22, 60, 45, 20])
            Text("\(flagEmoji(countryCode: "DE")) Falkenstein")
                .bodySecondary()
            Text("\(flagEmoji(countryCode: "us")) Ashburn")
                .bodySecondary()
            Text("\(flagEmoji(countryCode: "??")) Unknown")
                .bodySecondary()
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
