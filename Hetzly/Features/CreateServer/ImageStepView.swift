import HetznerKit
import SwiftUI

/// Step 2: system images grouped by `osFlavor`. Tapping a flavor row expands
/// it into a horizontal strip of version chips (newest images sort first
/// from `listImages`, so the first chip is the latest release) and
/// preselects that latest version if the flavor has no selection yet.
struct ImageStepView: View {
    var viewModel: CreateServerViewModel

    @State private var expandedFlavor: String?

    private static let preferredOrder = ["ubuntu", "debian", "fedora", "rocky", "alma", "centos"]

    private var flavors: [String] {
        let present = Set(viewModel.images.map(\.osFlavor))
        let ordered = Self.preferredOrder.filter { present.contains($0) }
        let extra = present.subtracting(Self.preferredOrder).sorted()
        return ordered + extra
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            SectionLabel("Choose an Image")

            VStack(spacing: Spacing.unit * 3) {
                ForEach(flavors, id: \.self) { flavor in
                    flavorSection(flavor)
                }
            }
        }
        .onAppear {
            if let selected = viewModel.selectedImage {
                expandedFlavor = selected.osFlavor
            }
        }
    }

    private func images(for flavor: String) -> [HetznerImage] {
        viewModel.images.filter { $0.osFlavor == flavor }
    }

    private func flavorSection(_ flavor: String) -> some View {
        let flavorImages = images(for: flavor)
        let isExpanded = expandedFlavor == flavor
        let selectedInFlavor = viewModel.selectedImage.flatMap { $0.osFlavor == flavor ? $0 : nil }

        return GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                Button {
                    withAnimation(.snappy) {
                        expandedFlavor = isExpanded ? nil : flavor
                        if selectedInFlavor == nil, let newest = flavorImages.first {
                            viewModel.selectedImage = newest
                        }
                    }
                } label: {
                    HStack {
                        Text(flavorDisplayName(flavor))
                            .bodyPrimary()
                            .fontWeight(.semibold)
                        Spacer()
                        if let selectedInFlavor {
                            Text(selectedInFlavor.osVersion ?? selectedInFlavor.name ?? "")
                                .hetzlyMonoNumbers()
                                .foregroundStyle(HetzlyColors.textSecondary)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(HetzlyColors.textTertiary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    versionChips(flavorImages)
                }
            }
        }
    }

    private func versionChips(_ flavorImages: [HetznerImage]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.unit * 2) {
                ForEach(flavorImages) { image in
                    versionChip(image)
                }
            }
        }
    }

    private func versionChip(_ image: HetznerImage) -> some View {
        let isSelected = viewModel.selectedImage?.id == image.id
        return Button {
            withAnimation(.snappy) { viewModel.selectedImage = image }
        } label: {
            HStack(spacing: Spacing.unit) {
                Text(image.osVersion ?? image.name ?? "—")
                Text(image.architecture == .arm ? "Arm" : "x86")
                    .foregroundStyle(isSelected ? HetzlyColors.textPrimary.opacity(0.7) : HetzlyColors.textTertiary)
            }
            .font(.system(size: 13, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(isSelected ? HetzlyColors.textPrimary : HetzlyColors.textSecondary)
            .padding(.horizontal, Spacing.unit * 3)
            .padding(.vertical, Spacing.unit * 1.5)
            .background {
                Capsule(style: .continuous)
                    .fill(isSelected ? HetzlyColors.accent.opacity(0.9) : Color.white.opacity(0.06))
            }
        }
        .buttonStyle(.plain)
    }

    private func flavorDisplayName(_ flavor: String) -> String {
        switch flavor {
        case "ubuntu": "Ubuntu"
        case "debian": "Debian"
        case "fedora": "Fedora"
        case "rocky": "Rocky Linux"
        case "alma": "AlmaLinux"
        case "centos": "CentOS"
        default: flavor.capitalized
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        ScrollView {
            ImageStepView(viewModel: CreateServerPreviewFixtures.viewModel(step: .image))
                .padding(Spacing.screenMargin)
        }
    }
    .preferredColorScheme(.dark)
}
