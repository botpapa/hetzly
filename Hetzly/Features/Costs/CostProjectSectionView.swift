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
    /// Hetzner's list-price monthly equivalent for every Cloud server in
    /// this section, keyed by `Server.id` — used for the "list €X" hint next
    /// to a server row with a custom override, and passed on to
    /// `CloudServerPriceSheet` when opened from here.
    var cloudServerListPrices: [Int: Decimal] = [:]
    /// Cloud server overrides currently in effect, keyed by `Server.id` —
    /// drives the "custom" chip on an overridden server row.
    var cloudServerOverrides: [Int: Decimal] = [:]
    /// Presents `CloudServerPriceSheet` for the tapped Cloud server (id,
    /// display name, its list price if known). `nil` (the default) hides
    /// the edit-price affordance entirely, keeping every existing preview
    /// and call site compiling unchanged.
    var onEditCloudServerPrice: ((Int, String, Decimal?) -> Void)?

    @Environment(AppContainer.self) private var container
    @State private var updateTokenProject: ProjectRecord?

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
                    VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                        HStack(spacing: Spacing.unit * 2) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(HetzlyColors.statusError)
                            Text(errorMessage)
                                .bodySecondary()
                            Spacer(minLength: 0)
                        }
                        // Auth failures are recoverable in place: a
                        // rotated/revoked key just needs replacing, mirroring
                        // the Dashboard's per-project error row.
                        if section.isAuthError,
                           let project = container.projectsStore.projects.first(where: { $0.id == section.projectID }) {
                            Button("Update token…") {
                                updateTokenProject = project
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(HetzlyColors.accent)
                        }
                    }
                }
                .sheet(item: $updateTokenProject) { project in
                    UpdateTokenSheet(project: project)
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
                    .tracking(1.5)
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
                    fractionOfProject: CostsSupport.fraction(item.projectedMonth, of: section.projectedTotal),
                    isCustomPrice: isCustomPrice(for: item),
                    listPriceMonthly: cloudServerListPrice(for: item),
                    editAction: editAction(for: item)
                )
            }
        }
    }

    /// Parses the `Server.id` back out of a `CostItem`/`ItemCost` id built
    /// by `CostItemBuilder` (`"server-<id>"`) — `nil` for every other kind's
    /// id scheme (`"backup-…"`, `"volume-…"`, etc).
    private func cloudServerID(from itemID: String) -> Int? {
        guard itemID.hasPrefix("server-") else { return nil }
        return Int(itemID.dropFirst("server-".count))
    }

    private func isCustomPrice(for item: CostSummary.ItemCost) -> Bool {
        guard item.kind == .server, let id = cloudServerID(from: item.id) else { return false }
        return cloudServerOverrides[id] != nil
    }

    private func cloudServerListPrice(for item: CostSummary.ItemCost) -> Decimal? {
        guard item.kind == .server, let id = cloudServerID(from: item.id) else { return nil }
        return cloudServerListPrices[id]
    }

    /// `nil` unless this is a Cloud server row and a handler was supplied —
    /// `CostItemRow` only shows the edit-price affordance when this is
    /// non-nil.
    private func editAction(for item: CostSummary.ItemCost) -> (() -> Void)? {
        guard item.kind == .server, let id = cloudServerID(from: item.id), let onEditCloudServerPrice else { return nil }
        let listPrice = cloudServerListPrices[id]
        return { onEditCloudServerPrice(id, item.name, listPrice) }
    }
}

/// One billable item: name + kind chip on the left, projected €/mo
/// (monospaced) with month-to-date secondary on the right, and a tiny
/// accent-tinted bar showing this item's share of the project total.
struct CostItemRow: View {
    let item: CostSummary.ItemCost
    let currency: String
    let fractionOfProject: Double
    /// `true` when this row's price is a user-entered override rather than
    /// Hetzner's list price — shows the accent-free "custom" chip.
    var isCustomPrice = false
    /// Hetzner's list price for this row, shown as a subtle secondary line
    /// only when `isCustomPrice` is also true (otherwise it's redundant with
    /// the amount already shown).
    var listPriceMonthly: Decimal?
    /// Presents the price-editing sheet for this row. `nil` hides the
    /// affordance entirely — only Cloud server rows get one.
    var editAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 1.5) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.unit * 2) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(HetzlyColors.textPrimary)
                        .lineLimit(1)
                    if isCustomPrice, let listPriceMonthly {
                        Text("list \(listPriceMonthly, format: .currency(code: currency))")
                            .font(.system(size: 11))
                            .foregroundStyle(HetzlyColors.textTertiary)
                    }
                }

                kindChip

                if isCustomPrice {
                    customChip
                }

                if let editAction {
                    Button(action: editAction) {
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 15))
                            .foregroundStyle(HetzlyColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit price")
                }

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

    /// Deliberately accent-free (unlike `kindChip`) — this is informational,
    /// not a call to action, per the design system's accent-discipline
    /// convention (accent reserved for true CTAs).
    private var customChip: some View {
        Text("custom")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(HetzlyColors.textSecondary)
            .padding(.horizontal, Spacing.unit * 1.5)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(HetzlyColors.textSecondary.opacity(0.14))
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
                    CostProjectSectionView(
                        section: CostsPreviewFixtures.productionSection,
                        currency: "EUR",
                        // server-1 (web-01) has a grandfathered override —
                        // demonstrates the "custom" chip, "list €X" hint,
                        // and edit-price pencil together.
                        cloudServerListPrices: [1: Decimal(string: "18.90") ?? 0],
                        cloudServerOverrides: [1: Decimal(string: "12.90") ?? 0],
                        onEditCloudServerPrice: { _, _, _ in }
                    )
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
