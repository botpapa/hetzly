import SwiftUI

/// The Dashboard's headline card: this month's cost burn so far, plus the
/// full-month projection. The idle mascot (when everything is healthy and
/// enabled) perches on the card's top-trailing edge.
///
/// No daily-accrual sparkline: `CostSummary` only exposes month-to-date and
/// projected totals, not a time series, so faking one isn't an option —
/// this card intentionally omits it rather than fabricate data.
struct BurnCardView: View {
    let monthToDate: Decimal?
    let projected: Decimal?
    let currency: String
    let idleMascotState: MascotState?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                SectionLabel("This Month")

                Group {
                    if let monthToDate {
                        Text(monthToDate, format: .currency(code: currency))
                    } else {
                        Text("—")
                    }
                }
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(HetzlyColors.textPrimary)

                if let projected {
                    Text("projected \(projected, format: .currency(code: currency))")
                        .hetzlyMonoNumbers()
                        .foregroundStyle(HetzlyColors.textSecondary)
                }

                Text("Excludes traffic overage")
                    .caption()
            }
        }
        .overlay(alignment: .topTrailing) {
            if let idleMascotState {
                MascotView(state: idleMascotState, scale: 2)
                    .offset(x: -Spacing.unit * 2, y: -14)
                    .allowsHitTesting(false)
            }
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        VStack(spacing: Spacing.unit * 6) {
            BurnCardView(monthToDate: 42.18, projected: 96.40, currency: "EUR", idleMascotState: .idle)
            BurnCardView(monthToDate: 12.40, projected: 28.10, currency: "EUR", idleMascotState: .sleep)
            BurnCardView(monthToDate: nil, projected: nil, currency: "EUR", idleMascotState: nil)
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
