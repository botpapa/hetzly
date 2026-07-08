import HetznerKit
import SwiftUI

/// Step 3: an architecture toggle (x86/Arm) and a shared/dedicated filter
/// row above a list of matching server types, cheapest first, priced at the
/// step-1 location. `CreateServerViewModel.filteredServerTypes` already
/// hides types with no price entry at the selected location and deprecated
/// types unless one is already chosen — this view is purely presentational.
struct ServerTypeStepView: View {
    var viewModel: CreateServerViewModel

    @Namespace private var archNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            SectionLabel("Choose a Type")

            HStack {
                architectureToggle
                Spacer()
                cpuFilterRow
            }

            if viewModel.filteredServerTypes.isEmpty {
                GlassCard {
                    Text("No server types match this filter at the selected location.")
                        .bodySecondary()
                }
            } else {
                VStack(spacing: Spacing.unit * 2) {
                    ForEach(viewModel.filteredServerTypes) { type in
                        typeRow(type)
                    }
                }
            }
        }
    }

    // MARK: - Architecture toggle

    private var architectureToggle: some View {
        HStack(spacing: 2) {
            archSegment(.x86, label: "x86")
            archSegment(.arm, label: "Arm")
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
    }

    private func archSegment(_ architecture: Architecture, label: String) -> some View {
        let isSelected = viewModel.typeArchitectureFilter == architecture
        return Button {
            withAnimation(.snappy) { viewModel.typeArchitectureFilter = architecture }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? HetzlyColors.textPrimary : HetzlyColors.textSecondary)
                .padding(.horizontal, Spacing.unit * 3)
                .padding(.vertical, Spacing.unit * 1.5)
                .background {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(HetzlyColors.accent.opacity(0.9))
                            .matchedGeometryEffect(id: "arch-selection", in: archNamespace)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - CPU filter chips

    private var cpuFilterRow: some View {
        HStack(spacing: Spacing.unit * 2) {
            ForEach(CreateServerViewModel.CPUFilter.allCases) { filter in
                cpuFilterChip(filter)
            }
        }
    }

    private func cpuFilterChip(_ filter: CreateServerViewModel.CPUFilter) -> some View {
        let isSelected = viewModel.typeCPUFilter == filter
        return Button {
            withAnimation(.snappy) { viewModel.typeCPUFilter = filter }
        } label: {
            Text(filter.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? HetzlyColors.textPrimary : HetzlyColors.textSecondary)
                .padding(.horizontal, Spacing.unit * 3)
                .padding(.vertical, Spacing.unit * 1.5)
                .background {
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.14) : Color.white.opacity(0.04))
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Type row

    private func typeRow(_ type: ServerType) -> some View {
        let isSelected = viewModel.selectedServerType?.id == type.id
        let monthly = viewModel.selectedLocation.flatMap { viewModel.monthlyPrice(for: type, at: $0) }

        return Button {
            withAnimation(.snappy) { viewModel.selectedServerType = type }
        } label: {
            GlassCard(interactive: true) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Spacing.unit) {
                        HStack(spacing: Spacing.unit * 2) {
                            Text(type.name)
                                .bodyPrimary()
                                .fontWeight(.semibold)
                            if type.deprecated == true {
                                GlassChip("Deprecated", systemImage: "exclamationmark.triangle")
                            }
                        }
                        Text("\(type.cores) vCPU · \(formattedMemory(type.memory)) GB · \(type.disk) GB")
                            .hetzlyMonoNumbers()
                            .foregroundStyle(HetzlyColors.textSecondary)
                    }

                    Spacer(minLength: Spacing.unit * 2)

                    if let monthly {
                        Text(CurrencyFormat.string(monthly, currencyCode: viewModel.currencyCode) + "/mo")
                            .hetzlyMonoNumbers()
                            .foregroundStyle(HetzlyColors.textPrimary)
                    }
                }
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

    private func formattedMemory(_ memory: Double) -> String {
        memory.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(memory)) : String(format: "%.1f", memory)
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        ScrollView {
            ServerTypeStepView(viewModel: CreateServerPreviewFixtures.configuredViewModel())
                .padding(Spacing.screenMargin)
        }
    }
    .preferredColorScheme(.dark)
}
