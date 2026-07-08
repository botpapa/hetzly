import SwiftUI

/// The Costs tab's headline glass card: combined month-to-date across every
/// project (huge, monospaced), the projected full-month total, and a subtle
/// progress bar showing how much of the month has elapsed — so the gap
/// between the two numbers reads at a glance. Footnoted with the on-device
/// computation disclaimer.
struct CostsHeroCard: View {
    let monthToDate: Decimal?
    let projected: Decimal?
    let currency: String
    /// 0...1, how far through the current calendar month `now` is.
    let monthElapsedFraction: Double

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                HStack {
                    SectionLabel("Month to date")
                    Spacer()
                    Text(monthName)
                        .caption()
                }

                Group {
                    if let monthToDate {
                        Text(monthToDate, format: .currency(code: currency))
                    } else {
                        Text("—")
                    }
                }
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(HetzlyColors.textPrimary)
                .contentTransition(.numericText())

                if let projected {
                    Text("projected \(projected, format: .currency(code: currency)) this month")
                        .hetzlyMonoNumbers()
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(HetzlyColors.textSecondary)
                }

                monthProgressBar

                Text("Computed on-device from live inventory × Hetzner pricing. Excludes traffic overage & one-time fees.")
                    .caption()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Subtle: a 3pt track with the elapsed fraction in the accent at low
    /// opacity — a depth cue for the MTD/projected gap, not a chart.
    private var monthProgressBar: some View {
        VStack(alignment: .leading, spacing: Spacing.unit) {
            CostProportionBar(fraction: monthElapsedFraction)
            Text("\(Int((monthElapsedFraction * 100).rounded()))% of \(monthName) elapsed")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(HetzlyColors.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    private var monthName: String {
        Date().formatted(.dateTime.month(.wide))
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        VStack(spacing: Spacing.unit * 6) {
            CostsHeroCard(
                monthToDate: Decimal(string: "38.62") ?? 0,
                projected: Decimal(string: "154.90") ?? 0,
                currency: "EUR",
                monthElapsedFraction: 0.26
            )
            CostsHeroCard(
                monthToDate: nil,
                projected: nil,
                currency: "EUR",
                monthElapsedFraction: 0.26
            )
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
