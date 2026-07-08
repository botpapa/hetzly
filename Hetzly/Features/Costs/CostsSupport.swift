import Foundation
import SwiftUI

/// Small shared helpers for the Costs feature.
enum CostsSupport {
    /// Lossy `Decimal` → `Double` bridge, for *geometry only* (bar widths,
    /// chart angles) — never for money math or money display, which stay
    /// `Decimal` end-to-end per house rules.
    static func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    /// The proportion `part` makes of `total`, clamped to 0...1, as a
    /// `Double` for layout. Returns 0 for a non-positive total.
    static func fraction(_ part: Decimal, of total: Decimal) -> Double {
        guard total > 0 else { return 0 }
        return min(max(double(part) / double(total), 0), 1)
    }
}

/// A thin, subtle horizontal proportion bar: `fraction` of the available
/// width filled with the given tint at 30% opacity over a faint track.
struct CostProportionBar: View {
    let fraction: Double
    var tint: Color = HetzlyColors.accent

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.06))
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.3))
                    .frame(width: max(geometry.size.width * fraction, fraction > 0 ? 3 : 0))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        VStack(spacing: Spacing.unit * 4) {
            CostProportionBar(fraction: 0.85)
            CostProportionBar(fraction: 0.4, tint: HetzlyColors.statusRunning)
            CostProportionBar(fraction: 0.05)
            CostProportionBar(fraction: 0)
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
