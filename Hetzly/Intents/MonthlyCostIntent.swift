import AppIntents
import HetznerKit

/// "What's my Hetzner bill?" — no parameters, adds up every project's
/// server costs live. Mirrors `CostsViewModel`'s server-cost path
/// (`listServers` + `pricing()` → `CostItemBuilder` → `CostEngine`) but
/// deliberately narrower: servers only, no volumes/IPs/load balancers/Robot
/// — a full resource sweep per project is the right depth for the Costs
/// tab's UI, not for a one-shot Siri round trip. A project without a
/// reachable client (missing token, offline) is skipped rather than failing
/// the whole intent, same isolation `CostsViewModel.fetchProject` uses.
struct MonthlyCostIntent: AppIntent {
    static let title: LocalizedStringResource = "Monthly Hetzner Cost"
    static let description = IntentDescription(
        "Adds up this month's Hetzner Cloud server spend across every project, live from Hetzner's pricing API."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let projectsStore = IntentEnvironment.projectsStore(), !projectsStore.projects.isEmpty else {
            throw HetzlyIntentError.noProjects
        }

        let items = await Self.fetchAllCostItems(projects: projectsStore.projects)
        guard !items.isEmpty else {
            throw HetzlyIntentError.noBillableResources
        }

        let summary = CostEngine.summary(items: items.costItems, now: Date(), calendar: .current, currency: items.currency)
        let monthToDate = Self.formatCurrency(summary.monthToDate, currency: summary.currency)
        let projected = Self.formatCurrency(summary.projectedMonthTotal, currency: summary.currency)
        let dialogText = "This month so far: \(monthToDate), projected \(projected)."

        return .result(value: dialogText, dialog: IntentDialog(stringLiteral: dialogText))
    }

    private struct FetchResult: Sendable {
        var costItems: [CostItem] = []
        var currency = "EUR"
        var isEmpty: Bool { costItems.isEmpty }
    }

    /// Fetches every project concurrently, exactly like
    /// `CostsViewModel.fetchAllProjects` — one slow/offline project never
    /// blocks the others.
    @MainActor
    private static func fetchAllCostItems(projects: [ProjectRecord]) async -> FetchResult {
        await withTaskGroup(of: (items: [CostItem], currency: String?).self) { group in
            for project in projects {
                let projectID = project.id
                group.addTask {
                    await Self.fetchProjectCostItems(projectID: projectID)
                }
            }

            var result = FetchResult()
            for await fetch in group {
                result.costItems.append(contentsOf: fetch.items)
                if let currency = fetch.currency {
                    result.currency = currency
                }
            }
            return result
        }
    }

    private static func fetchProjectCostItems(projectID: UUID) async -> (items: [CostItem], currency: String?) {
        guard let client = try? await IntentEnvironment.cloudClient(forProjectID: projectID) else {
            return ([], nil)
        }
        do {
            async let serversTask = client.listServers()
            async let pricingTask = client.pricing()
            let servers = try await serversTask
            let pricing = try await pricingTask
            return (CostItemBuilder.items(servers: servers, pricing: pricing), pricing.currency)
        } catch {
            return ([], nil)
        }
    }

    private static func formatCurrency(_ value: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value) \(currency)"
    }
}
