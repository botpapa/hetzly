import SwiftUI

/// PRICE row on the Control tab: the server's effective monthly cost.
/// Hetzner's `/pricing` endpoint only ever returns *current list* price — a
/// server bought under an older price list, or with a returning-customer
/// discount, over-reports there (see CONTRACTS.md's "Pricing-accuracy +
/// server-data" wave) — so a manual override from `CloudServerPriceStore`
/// (worker PA's, `Hetzly/Features/Costs/`) takes precedence when set.
/// Tapping opens `CloudServerPriceSheet` (also PA's) to set, edit, or clear
/// that override — `ServerDetailView` owns the sheet presentation, this view
/// just reports the tap.
struct ServerPriceSection: View {
    /// This server type's list monthly price at its own location, matched
    /// from the cached `/pricing` catalog (`ServerDetailViewModel.listPriceMonthly`).
    /// `nil` while pricing hasn't loaded yet or has no entry for this
    /// server's type.
    let listPriceMonthly: Decimal?
    let currency: String
    /// The user's manually entered monthly price, if any
    /// (`CloudServerPriceStore.price(for:)`).
    let override: Decimal?
    var onTap: () -> Void

    private var effectivePrice: Decimal? { override ?? listPriceMonthly }

    /// Only worth showing "list €X" next to the big number when an override
    /// is set AND it actually differs from list — otherwise it's redundant
    /// with the number already shown.
    private var showsListComparison: Bool {
        guard let override, let listPriceMonthly else { return false }
        return override != listPriceMonthly
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            SectionLabel("Price")

            GlassCard(interactive: true) {
                HStack(alignment: .top, spacing: Spacing.unit * 3) {
                    VStack(alignment: .leading, spacing: Spacing.unit) {
                        if let effectivePrice {
                            HStack(alignment: .firstTextBaseline, spacing: Spacing.unit * 2) {
                                Text("\(effectivePrice, format: .currency(code: currency))/mo")
                                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundStyle(HetzlyColors.textPrimary)

                                if showsListComparison, let listPriceMonthly {
                                    Text("list \(listPriceMonthly, format: .currency(code: currency))")
                                        .font(.system(size: 13, design: .monospaced))
                                        .monospacedDigit()
                                        .strikethrough()
                                        .foregroundStyle(HetzlyColors.textTertiary)
                                }
                            }

                            Text(override != nil ? "Your price" : "Tap to set what you actually pay")
                                .font(.system(size: 13, weight: override == nil ? .semibold : .regular))
                                .foregroundStyle(override == nil ? HetzlyColors.accent : HetzlyColors.textTertiary)
                        } else {
                            Text("Price unavailable")
                                .bodySecondary()
                        }
                    }

                    Spacer(minLength: Spacing.unit * 2)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(HetzlyColors.textTertiary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
        }
    }
}

#Preview("List price only") {
    ZStack {
        CanvasBackground()
        ServerPriceSection(listPriceMonthly: Decimal(string: "6.90"), currency: "EUR", override: nil, onTap: {})
            .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}

#Preview("Override set, differs from list") {
    ZStack {
        CanvasBackground()
        ServerPriceSection(
            listPriceMonthly: Decimal(string: "69.49"),
            currency: "EUR",
            override: Decimal(string: "25.49"),
            onTap: {}
        )
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}

#Preview("Pricing unavailable") {
    ZStack {
        CanvasBackground()
        ServerPriceSection(listPriceMonthly: nil, currency: "EUR", override: nil, onTap: {})
            .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
