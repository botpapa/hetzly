import SwiftUI

/// Full price breakdown for a product/listing: monthly net+gross, one-time
/// setup fee net+gross, and a first-month explainer so the very first
/// invoice amount is never a surprise. Reused by both detail screens and the
/// review screen.
struct PriceBreakdownCard: View {
    let monthlyNet: Decimal
    let monthlyGross: Decimal
    let setupNet: Decimal
    let setupGross: Decimal
    let currency: String

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                Label("Price Breakdown", systemImage: "eurosign.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HetzlyColors.textSecondary)

                row(title: "Monthly (net)", amount: monthlyNet)
                row(title: "Monthly (incl. VAT)", amount: monthlyGross, emphasized: true)

                Divider().overlay(HetzlyColors.textTertiary.opacity(0.15))

                row(title: "Setup Fee (net)", amount: setupNet)
                row(title: "Setup Fee (incl. VAT)", amount: setupGross, emphasized: true)

                Divider().overlay(HetzlyColors.textTertiary.opacity(0.15))

                Text(firstMonthExplainer)
                    .caption()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var firstMonthExplainer: String {
        let setupText = setupGross > 0
            ? " plus the one-time \(formatted(setupGross)) setup fee"
            : ""
        return "Your first invoice covers this month's \(formatted(monthlyGross))\(setupText). "
            + "After that you're billed \(formatted(monthlyGross))/mo until you cancel the server."
    }

    private func row(title: String, amount: Decimal, emphasized: Bool = false) -> some View {
        HStack {
            Text(title).bodySecondary()
            Spacer()
            Text(formatted(amount))
                .hetzlyMonoNumbers()
                .foregroundStyle(emphasized ? HetzlyColors.textPrimary : HetzlyColors.textSecondary)
                .fontWeight(emphasized ? .semibold : .regular)
        }
    }

    private func formatted(_ amount: Decimal) -> String {
        OrderCurrencyFormat.string(amount, currencyCode: currency)
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        PriceBreakdownCard(monthlyNet: 39, monthlyGross: 46.41, setupNet: 0, setupGross: 0, currency: "EUR")
            .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
