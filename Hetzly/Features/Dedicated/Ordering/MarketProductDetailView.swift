import SwiftUI

/// Server Market product detail: full spec sheet, price breakdown, and the
/// required SSH key multi-select. Market servers are ordered as-is — Robot's
/// market order has no location/dist parameter, so there's no picker for
/// either here. "Continue to Review" is disabled until at least one key is
/// selected — Robot has no password install path.
struct MarketProductDetailView: View {
    let listing: MarketListing
    let sshKeys: [SSHKeyOption]
    var onContinue: (OrderDraft) -> Void

    @State private var selectedFingerprints: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.unit * 5) {
                header

                specSheet

                SSHKeyMultiSelectSection(keys: sshKeys, selection: $selectedFingerprints)

                PriceBreakdownCard(
                    monthlyNet: listing.monthlyNet,
                    monthlyGross: listing.monthlyGross,
                    setupNet: listing.setupNet,
                    setupGross: listing.setupGross,
                    currency: listing.currency
                )
            }
            .padding(Spacing.screenMargin)
            .padding(.bottom, Spacing.unit * 10)
        }
        .safeAreaInset(edge: .bottom) {
            footer
        }
        .navigationTitle(listing.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            HStack(spacing: Spacing.unit * 2) {
                if listing.fixedPrice {
                    GlassChip("Fixed Price", systemImage: "lock.fill")
                } else if listing.isNextReduceSoon() {
                    GlassChip("Reduces Soon", systemImage: "arrow.down.right.circle")
                }
                if let datacenter = listing.datacenter {
                    GlassChip(datacenter, systemImage: "building.2")
                }
            }
            Text(listing.cpu).bodyPrimary()
            HStack(spacing: Spacing.unit * 3) {
                Text("\(listing.memoryGB) GB RAM").hetzlyMonoNumbers().foregroundStyle(HetzlyColors.textSecondary)
                Text(listing.hddSummary).hetzlyMonoNumbers().foregroundStyle(HetzlyColors.textSecondary)
            }
        }
    }

    private var specSheet: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Specification")
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                    specRow(title: "Traffic", value: listing.traffic)
                    ForEach(listing.descriptionLines, id: \.self) { line in
                        Text(line).bodySecondary()
                    }
                }
            }
        }
    }

    private func specRow(title: String, value: String) -> some View {
        HStack {
            Text(title).caption()
            Spacer()
            Text(value).bodySecondary()
        }
    }

    private var footer: some View {
        VStack(spacing: Spacing.unit * 2) {
            Divider().overlay(HetzlyColors.textTertiary.opacity(0.15))
            PrimaryCTA(title: "Continue to Review") {
                let keys = sshKeys.filter { selectedFingerprints.contains($0.fingerprint) }
                onContinue(.market(listing, sshKeys: keys))
            }
            .disabled(selectedFingerprints.isEmpty)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.unit * 2)
        .padding(.bottom, Spacing.unit * 3)
        .background {
            Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 0)).ignoresSafeArea(edges: .bottom)
        }
    }
}

#Preview {
    NavigationStack {
        ZStack {
            CanvasBackground()
            MarketProductDetailView(
                listing: OrderPreviewFixtures.marketListings[0],
                sshKeys: OrderPreviewFixtures.sshKeys,
                onContinue: { _ in }
            )
        }
    }
    .preferredColorScheme(.dark)
}
