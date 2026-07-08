import Foundation
import HetznerKit

/// Preview-only fixtures for the Costs feature: rich multi-project,
/// all-kinds state built directly from `CostSummary.ItemCost` values (no
/// network, no `CostEngine` run needed — display types are seeded exactly).
enum CostsPreviewFixtures {
    private static func money(_ string: String) -> Decimal {
        Decimal(string: string) ?? 0
    }

    // MARK: - Item costs

    static let productionItems: [CostSummary.ItemCost] = [
        CostSummary.ItemCost(id: "server-1", name: "web-01", kind: .server, monthToDate: money("3.41"), projectedMonth: money("12.90")),
        CostSummary.ItemCost(id: "server-2", name: "db-01", kind: .server, monthToDate: money("6.87"), projectedMonth: money("25.99")),
        CostSummary.ItemCost(id: "server-3", name: "worker-01", kind: .server, monthToDate: money("1.71"), projectedMonth: money("6.49")),
        CostSummary.ItemCost(id: "backup-2", name: "db-01 backups", kind: .backup, monthToDate: money("1.37"), projectedMonth: money("5.20")),
        CostSummary.ItemCost(id: "volume-1", name: "db-data", kind: .volume, monthToDate: money("1.27"), projectedMonth: money("4.80")),
        CostSummary.ItemCost(id: "volume-2", name: "backups-cold", kind: .volume, monthToDate: money("2.54"), projectedMonth: money("9.60")),
        CostSummary.ItemCost(id: "primary-ip-1", name: "web-01-ip", kind: .primaryIP, monthToDate: money("0.16"), projectedMonth: money("0.60")),
        CostSummary.ItemCost(id: "primary-ip-2", name: "db-01-ip", kind: .primaryIP, monthToDate: money("0.16"), projectedMonth: money("0.60")),
        CostSummary.ItemCost(id: "floating-ip-1", name: "failover-ip", kind: .floatingIP, monthToDate: money("0.90"), projectedMonth: money("3.41")),
        CostSummary.ItemCost(id: "load-balancer-1", name: "lb-prod", kind: .loadBalancer, monthToDate: money("1.42"), projectedMonth: money("5.39")),
    ]

    static let stagingItems: [CostSummary.ItemCost] = [
        CostSummary.ItemCost(id: "server-10", name: "staging-01", kind: .server, monthToDate: money("2.29"), projectedMonth: money("8.66")),
        CostSummary.ItemCost(id: "server-11", name: "ci-runner", kind: .server, monthToDate: money("3.43"), projectedMonth: money("12.97")),
        CostSummary.ItemCost(id: "primary-ip-10", name: "staging-ip", kind: .primaryIP, monthToDate: money("0.16"), projectedMonth: money("0.60")),
    ]

    // MARK: - Sections

    static let productionSection = CostsViewModel.ProjectSection(
        projectID: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001") ?? UUID(),
        projectName: "Production",
        itemCosts: productionItems.sorted { $0.projectedMonth > $1.projectedMonth },
        projectedTotal: money("74.98"),
        monthToDate: money("19.81"),
        errorMessage: nil
    )

    static let stagingSection = CostsViewModel.ProjectSection(
        projectID: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002") ?? UUID(),
        projectName: "Staging",
        itemCosts: stagingItems.sorted { $0.projectedMonth > $1.projectedMonth },
        projectedTotal: money("22.23"),
        monthToDate: money("5.88"),
        errorMessage: nil
    )

    static let failedSection = CostsViewModel.ProjectSection(
        projectID: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000003") ?? UUID(),
        projectName: "Playground",
        itemCosts: [],
        projectedTotal: 0,
        monthToDate: 0,
        errorMessage: "A network error occurred. Please check your connection and try again."
    )

    static let emptySection = CostsViewModel.ProjectSection(
        projectID: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000004") ?? UUID(),
        projectName: "Sandbox",
        itemCosts: [],
        projectedTotal: 0,
        monthToDate: 0,
        errorMessage: nil
    )

    // MARK: - Kind shares (combined donut)

    static let kindShares: [CostsViewModel.KindShare] = [
        CostsViewModel.KindShare(kind: .server, projected: money("67.01")),
        CostsViewModel.KindShare(kind: .dedicated, projected: money("39.00")),
        CostsViewModel.KindShare(kind: .volume, projected: money("14.40")),
        CostsViewModel.KindShare(kind: .loadBalancer, projected: money("5.39")),
        CostsViewModel.KindShare(kind: .backup, projected: money("5.20")),
        CostsViewModel.KindShare(kind: .floatingIP, projected: money("3.41")),
        CostsViewModel.KindShare(kind: .primaryIP, projected: money("1.80")),
    ]

    // MARK: - View models

    @MainActor static var richViewModel: CostsViewModel {
        CostsViewModel(
            projectSections: [productionSection, stagingSection, failedSection],
            combinedMonthToDate: money("36.02"),
            combinedProjected: money("136.21"),
            currency: "EUR",
            kindShares: kindShares,
            monthElapsedFraction: 0.26
        )
    }

    @MainActor static var emptyViewModel: CostsViewModel {
        CostsViewModel(
            projectSections: [emptySection],
            combinedMonthToDate: nil,
            combinedProjected: nil,
            currency: "EUR",
            kindShares: [],
            monthElapsedFraction: 0.26
        )
    }

    static let manualEntries: [ManualCostEntry] = [
        ManualCostEntry(
            id: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000001") ?? UUID(),
            name: "AX42 dedicated",
            monthlyPrice: money("39.00"),
            note: "FSN1-DC14"
        ),
    ]
}
