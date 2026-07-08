import HetznerKit
import SwiftUI

/// The COSTS section of `ProjectDetailView`: this project's top-5 billable
/// items by projected monthly cost, reusing the Costs feature's `CostKind`
/// icon/name mapping (`CostKind+UI`, same app target) for the kind chip.
struct ProjectCostsSection: View {
    let items: [CostSummary.ItemCost]
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            SectionLabel("Costs")

            if items.isEmpty {
                GlassCard {
                    Text("No billable resources yet.")
                        .bodySecondary()
                }
            } else {
                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.unit * 4) {
                        ForEach(items) { item in
                            row(item)
                            if item.id != items.last?.id {
                                Divider().overlay(HetzlyColors.textTertiary.opacity(0.2))
                            }
                        }
                    }
                }
            }
        }
    }

    private func row(_ item: CostSummary.ItemCost) -> some View {
        HStack(alignment: .center, spacing: Spacing.unit * 3) {
            VStack(alignment: .leading, spacing: Spacing.unit) {
                Text(item.name)
                    .bodyPrimary()
                GlassChip(item.kind.displayName, systemImage: item.kind.systemImage)
            }
            Spacer(minLength: Spacing.unit * 2)
            Text(item.projectedMonth, format: .currency(code: currency))
                .hetzlyMonoNumbers()
                .foregroundStyle(HetzlyColors.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        ScrollView {
            VStack(spacing: Spacing.unit * 6) {
                ProjectCostsSection(
                    items: [
                        CostSummary.ItemCost(id: "server-1", name: "web-01", kind: .server, monthToDate: 3.41, projectedMonth: 12.90),
                        CostSummary.ItemCost(id: "volume-1", name: "db-data", kind: .volume, monthToDate: 1.27, projectedMonth: 4.80),
                        CostSummary.ItemCost(id: "primary-ip-1", name: "web-01-ip", kind: .primaryIP, monthToDate: 0.16, projectedMonth: 0.60),
                    ],
                    currency: "EUR"
                )
                ProjectCostsSection(items: [], currency: "EUR")
            }
            .padding(Spacing.screenMargin)
        }
    }
    .preferredColorScheme(.dark)
}
