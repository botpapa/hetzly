import Foundation
import HetznerKit

/// Preview-only fixtures for the Projects feature: a stand-in `ProjectRecord`
/// (previews never seed a real SwiftData store) plus a handful of
/// `ProjectDetailViewModel` states built directly from display types — no
/// network, no live `CloudClient`.
enum ProjectsPreviewFixtures {
    static let projectID = UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000001") ?? UUID()

    @MainActor
    static let project = ProjectRecord(id: projectID, name: "Personal", sortOrder: 0)

    private static func money(_ string: String) -> Decimal {
        Decimal(string: string) ?? 0
    }

    static let servers: [ServerListItem] = [
        ServerListItem(projectID: projectID, serverID: 1, name: "web-01", status: .running, typeName: "cx22", city: "Falkenstein", countryCode: "DE"),
        ServerListItem(projectID: projectID, serverID: 2, name: "db-01", status: .running, typeName: "cx32", city: "Falkenstein", countryCode: "DE"),
        ServerListItem(projectID: projectID, serverID: 3, name: "worker-03", status: .stopping, typeName: "cx22", city: "Ashburn", countryCode: "US"),
    ]

    static let counts = ProjectDetailViewModel.ResourceCounts(
        volumes: 2, networks: 1, firewalls: 1, loadBalancers: 1,
        primaryIPs: 3, floatingIPs: 1, sshKeys: 2, certificates: 0
    )

    static let topCostItems: [CostSummary.ItemCost] = [
        CostSummary.ItemCost(id: "server-2", name: "db-01", kind: .server, monthToDate: money("6.87"), projectedMonth: money("25.99")),
        CostSummary.ItemCost(id: "server-1", name: "web-01", kind: .server, monthToDate: money("3.41"), projectedMonth: money("12.90")),
        CostSummary.ItemCost(id: "load-balancer-1", name: "lb-prod", kind: .loadBalancer, monthToDate: money("1.42"), projectedMonth: money("5.39")),
        CostSummary.ItemCost(id: "volume-1", name: "db-data", kind: .volume, monthToDate: money("1.27"), projectedMonth: money("4.80")),
        CostSummary.ItemCost(id: "primary-ip-1", name: "web-01-ip", kind: .primaryIP, monthToDate: money("0.16"), projectedMonth: money("0.60")),
    ]

    @MainActor
    static var loadedViewModel: ProjectDetailViewModel {
        ProjectDetailViewModel(
            projectID: projectID,
            servers: servers,
            counts: counts,
            monthToDate: money("13.13"),
            projected: money("49.68"),
            currency: "EUR",
            topCostItems: topCostItems,
            loadState: .loaded
        )
    }

    @MainActor
    static var staleViewModel: ProjectDetailViewModel {
        ProjectDetailViewModel(
            projectID: projectID,
            servers: servers,
            counts: counts,
            resourceErrors: ["A network error occurred. Please check your connection and try again."],
            monthToDate: money("13.13"),
            projected: money("49.68"),
            currency: "EUR",
            topCostItems: topCostItems,
            loadState: .loaded,
            isStale: true
        )
    }

    @MainActor
    static var emptyViewModel: ProjectDetailViewModel {
        ProjectDetailViewModel(
            projectID: projectID,
            servers: [],
            counts: ProjectDetailViewModel.ResourceCounts(),
            monthToDate: nil,
            projected: nil,
            currency: "EUR",
            topCostItems: [],
            loadState: .loaded
        )
    }

    @MainActor
    static var missingTokenViewModel: ProjectDetailViewModel {
        ProjectDetailViewModel(
            projectID: projectID,
            servers: servers,
            counts: ProjectDetailViewModel.ResourceCounts(),
            monthToDate: money("13.13"),
            projected: money("49.68"),
            currency: "EUR",
            topCostItems: topCostItems,
            loadState: .loaded,
            isStale: true,
            missingToken: true
        )
    }
}
