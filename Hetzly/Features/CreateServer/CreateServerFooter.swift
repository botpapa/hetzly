import SwiftUI

/// Sticky glass footer, visible through every configuring step: the live
/// €/mo price (big, monospaced, cross-fades on change), €/h underneath, and
/// the primary CTA — "Continue" on steps 1–3, "Create Server · €X.XX/mo" on
/// step 4 so the price is never a surprise at the moment of commitment.
struct CreateServerFooter: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var viewModel: CreateServerViewModel
    var onPrimary: () -> Void

    var body: some View {
        VStack(spacing: Spacing.unit * 3) {
            Divider().overlay(HetzlyColors.textTertiary.opacity(0.15))

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(monthlyText)
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(HetzlyColors.textPrimary)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: monthlyText)
                    Text(hourlyText)
                        .caption()
                }

                Spacer(minLength: Spacing.unit * 4)

                PrimaryCTA(title: ctaTitle, action: onPrimary)
                    .disabled(!viewModel.canContinue)
            }
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.unit * 2)
        .padding(.bottom, Spacing.unit * 3)
        .background(background)
    }

    @ViewBuilder
    private var background: some View {
        if reduceTransparency {
            Color(white: 0.12).ignoresSafeArea(edges: .bottom)
        } else {
            Color.clear
                .glassEffect(.regular, in: .rect(cornerRadius: 0))
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var monthlyText: String {
        guard let preview = viewModel.pricePreview else { return "—" }
        return CurrencyFormat.string(preview.monthlyNet, currencyCode: preview.currency) + "/mo"
    }

    private var hourlyText: String {
        guard let preview = viewModel.pricePreview else { return "Select a location and type" }
        return CurrencyFormat.string(preview.hourlyNet, currencyCode: preview.currency, fractionDigits: 3) + "/hr"
    }

    private var ctaTitle: String {
        guard viewModel.step == .config else { return "Continue" }
        guard let preview = viewModel.pricePreview else { return "Create Server" }
        return "Create Server · " + CurrencyFormat.string(preview.monthlyNet, currencyCode: preview.currency) + "/mo"
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        VStack {
            Spacer()
            CreateServerFooter(viewModel: CreateServerPreviewFixtures.configuredViewModel(), onPrimary: {})
        }
    }
    .preferredColorScheme(.dark)
}
