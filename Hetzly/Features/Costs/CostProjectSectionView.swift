import HetznerKit
import SwiftUI

/// One project's cost breakdown: a `GlassCard` containing per-kind subtotal
/// headers (icon + kind + subtotal) with each kind's item rows underneath,
/// everything sorted descending by projected monthly cost. A failed project
/// renders its inline error instead of (or alongside stale) rows — other
/// projects are unaffected.
struct CostProjectSectionView: View {
    let section: CostsViewModel.ProjectSection
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            NavigationLink(value: ProjectRoute(projectID: section.projectID)) {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel(section.projectName)
                    Spacer()
                    if section.projectedTotal > 0 {
                        Text(section.projectedTotal, format: .currency(code: currency))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(HetzlyColors.textSecondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HetzlyColors.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let errorMessage = section.errorMessage {
                GlassCard {
                    HStack(spacing: Spacing.unit * 2) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(HetzlyColors.statusError)
                        Text(errorMessage)
                            .bodySecondary()
                        Spacer(minLength: 0)
                    }
                }
            } else if section.itemCosts.isEmpty {
                GlassCard {
                    HStack {
                        Text("No billable resources in this project")
                            .bodySecondary()
                        Spacer(minLength: 0)
                    }
                }
            } else {
                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.unit * 4) {
                        ForEach(section.kindSubtotals) { subtotal in
                            kindGroup(subtotal)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func kindGroup(_ subtotal: CostsViewModel.KindSubtotal) -> some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2.5) {
            HStack(spacing: Spacing.unit * 1.5) {
                Image(systemName: subtotal.kind.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(subtotal.kind.tintColor)
                Text(subtotal.kind.displayName.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(HetzlyColors.textTertiary)
                Spacer()
                Text(subtotal.projectedTotal, format: .currency(code: currency))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(HetzlyColors.textSecondary)
            }

            ForEach(subtotal.items) { item in
                CostItemRow(
                    item: item,
                    currency: currency,
                    fractionOfProject: CostsSupport.fraction(item.projectedMonth, of: section.projectedTotal)
                )
            }
        }
    }
}

/// One billable item: name + kind chip on the left, projected €/mo
/// (monospaced) with month-to-date secondary on the right, and a tiny
/// accent-tinted bar showing this item's share of the project total.
struct CostItemRow: View {
    let item: CostSummary.ItemCost
    let currency: String
    let fractionOfProject: Double

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 1.5) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.unit * 2) {
                Text(item.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(HetzlyColors.textPrimary)
                    .lineLimit(1)

                kindChip

                Spacer(minLength: Spacing.unit * 2)

                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(item.projectedMonth, format: .currency(code: currency))/mo")
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(HetzlyColors.textPrimary)
                    Text("\(item.monthToDate, format: .currency(code: currency)) so far")
                        .font(.system(size: 12, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(HetzlyColors.textTertiary)
                }
            }

            CostProportionBar(fraction: fractionOfProject)
        }
        .accessibilityElement(children: .combine)
    }

    private var kindChip: some View {
        Text(item.kind.displayName)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(item.kind.tintColor)
            .padding(.horizontal, Spacing.unit * 1.5)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(item.kind.tintColor.opacity(0.14))
            )
            .lineLimit(1)
            .fixedSize()
    }
}

#Preview {
    NavigationStack {
        ZStack {
            CanvasBackground()
            ScrollView {
                VStack(spacing: Spacing.unit * 6) {
                    CostProjectSectionView(section: CostsPreviewFixtures.productionSection, currency: "EUR")
                    CostProjectSectionView(section: CostsPreviewFixtures.failedSection, currency: "EUR")
                    CostProjectSectionView(section: CostsPreviewFixtures.emptySection, currency: "EUR")
                }
                .padding(Spacing.screenMargin)
            }
        }
        .navigationDestination(for: ProjectRoute.self) { route in
            ProjectDetailView(route: route)
        }
    }
    .preferredColorScheme(.dark)
}
