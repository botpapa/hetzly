import SwiftUI

/// One Server Market row: name + CPU caption, RAM/disk monospaced chips, the
/// big monospaced €/mo price, and a "fixed price" or "reduces soon" chip.
/// The reduce chip is purely informational — no live countdown/timer, per
/// the M3 no-background-polling constraint.
struct MarketProductRow: View {
    let listing: MarketListing

    var body: some View {
        GlassCard(interactive: true) {
            VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(listing.name)
                            .bodyPrimary()
                            .fontWeight(.semibold)
                        Text(listing.cpu)
                            .caption()
                            .lineLimit(2)
                    }
                    Spacer(minLength: Spacing.unit * 3)
                    priceBlock
                }

                HStack(spacing: Spacing.unit * 2) {
                    MonoSpecChip(systemImage: "memorychip", text: "\(listing.memoryGB) GB RAM")
                    MonoSpecChip(systemImage: "internaldrive", text: listing.hddSummary)
                    Spacer(minLength: 0)
                    reduceChip
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var priceBlock: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(OrderCurrencyFormat.string(listing.monthlyNet, currencyCode: listing.currency))
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(HetzlyColors.textPrimary)
            Text("/mo net").caption()
        }
    }

    @ViewBuilder
    private var reduceChip: some View {
        if listing.fixedPrice {
            GlassChip("Fixed Price", systemImage: "lock.fill")
        } else if listing.isNextReduceSoon() {
            GlassChip("Reduces Soon", systemImage: "arrow.down.right.circle")
        }
    }
}

/// A capsule spec chip with a forced monospaced digit font — `GlassChip`
/// sets its own font internally (so an externally-applied `.font` modifier
/// wouldn't take effect), and RAM/disk figures specifically want
/// `hetzlyMonoNumbers()` per convention.
private struct MonoSpecChip: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let systemImage: String
    let text: String

    private var capsule: Capsule { Capsule(style: .continuous) }

    var body: some View {
        HStack(spacing: Spacing.unit) {
            Image(systemName: systemImage)
            Text(text).hetzlyMonoNumbers()
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(HetzlyColors.textPrimary)
        .padding(.horizontal, Spacing.unit * 3)
        .padding(.vertical, Spacing.unit * 1.5)
        .background {
            if reduceTransparency {
                capsule.fill(Color(white: 0.12)).overlay { capsule.strokeBorder(Color.white.opacity(0.08), lineWidth: 1) }
            } else {
                capsule.fill(Color.white.opacity(0.06))
            }
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        VStack(spacing: Spacing.unit * 3) {
            MarketProductRow(listing: OrderPreviewFixtures.marketListings[0])
            MarketProductRow(listing: OrderPreviewFixtures.marketListings[1])
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
