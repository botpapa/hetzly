import SwiftUI

/// One Standard product row: name, first description line, traffic, price
/// with setup fee, and location availability chips.
struct StandardProductRow: View {
    let listing: StandardListing

    var body: some View {
        GlassCard(interactive: true) {
            VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(listing.name)
                            .bodyPrimary()
                            .fontWeight(.semibold)
                        if let firstLine = listing.descriptionLines.first {
                            Text(firstLine).caption().lineLimit(2)
                        }
                        Text("Traffic: \(listing.traffic)").caption()
                    }
                    Spacer(minLength: Spacing.unit * 3)
                    priceBlock
                }

                if !listing.locationOptions.isEmpty {
                    HStack(spacing: Spacing.unit * 2) {
                        ForEach(listing.locationOptions, id: \.self) { location in
                            GlassChip(location, systemImage: "globe")
                        }
                    }
                }
            }
        }
    }

    /// Robot prices standard products per-location — the cheapest available
    /// location stands in as the representative "from" figure here; the
    /// detail screen resolves the exact price once a location is picked.
    @ViewBuilder
    private var priceBlock: some View {
        if let price = listing.cheapestPrice {
            VStack(alignment: .trailing, spacing: 2) {
                Text(OrderCurrencyFormat.string(price.monthlyNet, currencyCode: listing.currency))
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(HetzlyColors.textPrimary)
                Text("from /mo + " + OrderCurrencyFormat.string(price.setupNet, currencyCode: listing.currency) + " setup")
                    .caption()
            }
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        VStack(spacing: Spacing.unit * 3) {
            StandardProductRow(listing: OrderPreviewFixtures.standardListings[0])
            StandardProductRow(listing: OrderPreviewFixtures.standardListings[1])
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
