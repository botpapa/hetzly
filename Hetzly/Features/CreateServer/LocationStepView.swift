import HetznerKit
import SwiftUI

/// Step 1: a grid of location cards — flag, city, country, and a network
/// zone chip. Tapping a card selects it; the footer's "Continue" gates on a
/// selection existing.
struct LocationStepView: View {
    var viewModel: CreateServerViewModel

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.unit * 3),
        GridItem(.flexible(), spacing: Spacing.unit * 3),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            SectionLabel("Choose a Location")

            LazyVGrid(columns: columns, spacing: Spacing.unit * 3) {
                ForEach(viewModel.locations) { location in
                    locationCard(location)
                }
            }
        }
    }

    private func locationCard(_ location: Location) -> some View {
        let isSelected = viewModel.selectedLocation?.id == location.id
        return Button {
            withAnimation(.snappy) { viewModel.selectedLocation = location }
        } label: {
            GlassCard(interactive: true) {
                VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                    Text(flagEmoji(countryCode: location.country))
                        .font(.system(size: 28))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(location.city)
                            .bodyPrimary()
                            .fontWeight(.semibold)
                        Text(location.country)
                            .caption()
                    }

                    GlassChip(location.networkZone, systemImage: "network")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(HetzlyColors.accent, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        ScrollView {
            LocationStepView(viewModel: CreateServerPreviewFixtures.viewModel(step: .location))
                .padding(Spacing.screenMargin)
        }
    }
    .preferredColorScheme(.dark)
}
