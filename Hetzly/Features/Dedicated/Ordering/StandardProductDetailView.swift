import SwiftUI

/// Standard product detail: full spec sheet, price breakdown, dist +
/// location pickers, and the required SSH key multi-select.
struct StandardProductDetailView: View {
    let listing: StandardListing
    let sshKeys: [SSHKeyOption]
    var onContinue: (OrderDraft) -> Void

    @State private var selectedDist: String?
    @State private var selectedLocation: String?
    @State private var selectedFingerprints: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.unit * 5) {
                header

                specSheet

                if !listing.locationOptions.isEmpty {
                    locationPicker
                }

                if !listing.distOptions.isEmpty {
                    distPicker
                }

                SSHKeyMultiSelectSection(keys: sshKeys, selection: $selectedFingerprints)

                if let resolvedPrice {
                    PriceBreakdownCard(
                        monthlyNet: resolvedPrice.monthlyNet,
                        monthlyGross: resolvedPrice.monthlyGross,
                        setupNet: resolvedPrice.setupNet,
                        setupGross: resolvedPrice.setupGross,
                        currency: listing.currency
                    )
                }
            }
            .padding(Spacing.screenMargin)
            .padding(.bottom, Spacing.unit * 10)
        }
        .safeAreaInset(edge: .bottom) {
            footer
        }
        .navigationTitle(listing.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedDist == nil { selectedDist = listing.distOptions.first }
            if selectedLocation == nil { selectedLocation = listing.locationOptions.first }
        }
    }

    /// The price for the currently selected location — recomputed live as
    /// `selectedLocation` changes, since Robot prices standard products
    /// per-location rather than at a single flat rate.
    private var resolvedPrice: StandardLocationPrice? {
        listing.price(at: selectedLocation)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            if let firstLine = listing.descriptionLines.first {
                Text(firstLine).bodyPrimary()
            }
            Text("Traffic: \(listing.traffic)").caption()
        }
    }

    private var specSheet: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Specification")
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                    ForEach(listing.descriptionLines, id: \.self) { line in
                        Text(line).bodySecondary()
                    }
                }
            }
        }
    }

    private var locationPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Location")
            HStack(spacing: Spacing.unit * 2) {
                ForEach(listing.locationOptions, id: \.self) { location in
                    let isSelected = selectedLocation == location
                    Button {
                        withAnimation(.snappy) { selectedLocation = location }
                    } label: {
                        GlassChip(location, systemImage: isSelected ? "checkmark" : "globe")
                    }
                    .buttonStyle(.plain)
                    .overlay {
                        if isSelected {
                            Capsule().strokeBorder(HetzlyColors.accent, lineWidth: 1.5)
                        }
                    }
                }
            }
        }
    }

    private var distPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Operating System")
            Picker("Distribution", selection: Binding(get: { selectedDist ?? listing.distOptions.first ?? "" }, set: { selectedDist = $0 })) {
                ForEach(listing.distOptions, id: \.self) { dist in
                    Text(dist).tag(dist)
                }
            }
            .pickerStyle(.menu)
            .tint(HetzlyColors.textPrimary)
        }
    }

    private var footer: some View {
        VStack(spacing: Spacing.unit * 2) {
            Divider().overlay(HetzlyColors.textTertiary.opacity(0.15))
            PrimaryCTA(title: "Continue to Review") {
                guard let resolvedPrice else { return }
                let keys = sshKeys.filter { selectedFingerprints.contains($0.fingerprint) }
                onContinue(.standard(listing, price: resolvedPrice, dist: selectedDist, sshKeys: keys))
            }
            .disabled(selectedFingerprints.isEmpty || resolvedPrice == nil)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.unit * 2)
        .padding(.bottom, Spacing.unit * 3)
        .glassFooterBackground()
    }
}

#Preview {
    NavigationStack {
        ZStack {
            CanvasBackground()
            StandardProductDetailView(
                listing: OrderPreviewFixtures.standardListings[0],
                sshKeys: OrderPreviewFixtures.sshKeys,
                onContinue: { _ in }
            )
        }
    }
    .preferredColorScheme(.dark)
}
