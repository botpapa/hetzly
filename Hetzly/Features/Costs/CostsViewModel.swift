import Foundation
import HetznerKit
import Observation

/// Drives the Costs tab: aggregates every billable resource across every
/// project — servers, volumes, primary IPs, floating IPs, load balancers —
/// plus manually entered fixed costs (`ManualCostEntry`), and reduces them
/// through `CostEngine` both per-project and combined. Entirely on-device:
/// the only network calls are the same list/pricing endpoints Dashboard
/// already uses, and every dollar (euro) figure downstream is pure
/// `Decimal` math against that live inventory.
///
/// ## Concurrency
/// Every project is fetched concurrently with every other project
/// (`withTaskGroup`), and within a project its five resource lists are
/// fetched concurrently with each other (`async let`) — mirroring
/// `DashboardViewModel.refreshLive`'s per-project isolation. A project whose
/// fetch fails (missing token, network error, no pricing available)
/// surfaces an inline `errorMessage` on its own section only; every other
/// project still computes normally.
@MainActor
@Observable
final class CostsViewModel {
    struct ProjectSection: Identifiable, Sendable {
        let projectID: UUID
        var projectName: String
        var itemCosts: [CostSummary.ItemCost]
        var projectedTotal: Decimal
        var monthToDate: Decimal
        var errorMessage: String?

        var id: UUID { projectID }

        /// Per-kind subtotals for this project, sorted descending by
        /// projected cost — each subtotal's own items are sorted descending
        /// too, matching `CostEngine`'s per-item ordering.
        var kindSubtotals: [KindSubtotal] {
            let grouped = Dictionary(grouping: itemCosts, by: \.kind)
            return grouped
                .map { kind, items in
                    KindSubtotal(
                        kind: kind,
                        projectedTotal: items.reduce(0) { $0 + $1.projectedMonth },
                        items: items.sorted { $0.projectedMonth > $1.projectedMonth }
                    )
                }
                .sorted { $0.projectedTotal > $1.projectedTotal }
        }
    }

    struct KindSubtotal: Identifiable {
        let kind: CostKind
        let projectedTotal: Decimal
        let items: [CostSummary.ItemCost]
        var id: CostKind { kind }
    }

    struct KindShare: Identifiable, Equatable {
        let kind: CostKind
        let projected: Decimal
        var id: CostKind { kind }
    }

    private(set) var projectSections: [ProjectSection] = []
    private(set) var combinedMonthToDate: Decimal?
    private(set) var combinedProjected: Decimal?
    private(set) var currency = "EUR"
    private(set) var kindShares: [KindShare] = []
    private(set) var monthElapsedFraction: Double = 0
    private(set) var isLoading = false
    private(set) var isRefreshing = false

    /// Per-project pricing memo (TTL 24h), mirroring
    /// `DashboardViewModel.pricingCache`: this view model is its own
    /// single-consumer, `@MainActor`-serialized surface, so a plain
    /// dictionary is enough — no need for the shared `ResponseCache` actor.
    private var pricingCache: [UUID: (pricing: Pricing, fetchedAt: Date)] = [:]
    private let pricingTTL: TimeInterval = 24 * 60 * 60

    init() {}

    /// Preview/test-only entry point: seeds state directly, no network or
    /// `AppContainer` involved.
    init(
        projectSections: [ProjectSection] = [],
        combinedMonthToDate: Decimal? = nil,
        combinedProjected: Decimal? = nil,
        currency: String = "EUR",
        kindShares: [KindShare] = [],
        monthElapsedFraction: Double = 0
    ) {
        self.projectSections = projectSections
        self.combinedMonthToDate = combinedMonthToDate
        self.combinedProjected = combinedProjected
        self.currency = currency
        self.kindShares = kindShares
        self.monthElapsedFraction = monthElapsedFraction
    }

    /// True once we know for certain there is nothing to show: no project
    /// has any billable resource, and there are no manual entries either.
    var isEmpty: Bool {
        combinedProjected == nil
    }

    // MARK: - Lifecycle

    func load(container: AppContainer, manualEntries: [ManualCostEntry]) async {
        isLoading = true
        await refresh(container: container, manualEntries: manualEntries)
        isLoading = false
    }

    func refresh(container: AppContainer, manualEntries: [ManualCostEntry]) async {
        isRefreshing = true
        defer { isRefreshing = false }

        let projects = container.projectsStore.projects
        let now = Date()
        let calendar = Calendar.current

        let targets = projects.map { project in
            FetchTarget(
                projectID: project.id,
                projectName: project.name,
                client: container.cloudClient(for: project.id),
                cachedPricing: cachedPricing(for: project.id, now: now)
            )
        }

        let fetches: [ProjectFetch]
        if targets.isEmpty {
            fetches = []
        } else {
            fetches = await withTaskGroup(of: ProjectFetch.self) { group in
                for target in targets {
                    group.addTask { await Self.fetchProject(target) }
                }
                var results: [ProjectFetch] = []
                results.reserveCapacity(targets.count)
                for await result in group {
                    results.append(result)
                }
                return results
            }
        }

        for fetch in fetches {
            if let freshPricing = fetch.freshPricing {
                pricingCache[fetch.projectID] = (freshPricing, now)
            }
        }

        recompute(manualEntries: manualEntries, fetches: fetches, now: now, calendar: calendar)
    }

    private func cachedPricing(for projectID: UUID, now: Date) -> Pricing? {
        guard let cached = pricingCache[projectID], now.timeIntervalSince(cached.fetchedAt) < pricingTTL else {
            return nil
        }
        return cached.pricing
    }

    // MARK: - Per-project fetch

    private struct FetchTarget: Sendable {
        let projectID: UUID
        let projectName: String
        let client: CloudClient?
        let cachedPricing: Pricing?
    }

    private struct ProjectFetch: Sendable {
        let projectID: UUID
        let projectName: String
        let items: [CostItem]
        let currency: String?
        /// Non-nil only when this fetch actually hit the network for
        /// pricing (i.e. the cache was cold) — signals the caller to write
        /// it back into `pricingCache`.
        let freshPricing: Pricing?
        let errorMessage: String?
    }

    /// Fetches one project's five resource lists (concurrently) plus
    /// pricing, then adapts everything into `CostItem`s. Never throws out to
    /// the caller: any failure becomes this project's isolated
    /// `errorMessage` instead.
    private static func fetchProject(_ target: FetchTarget) async -> ProjectFetch {
        guard let client = target.client else {
            return ProjectFetch(
                projectID: target.projectID, projectName: target.projectName,
                items: [], currency: nil, freshPricing: nil,
                errorMessage: "No token configured for this project."
            )
        }

        do {
            async let serversTask = client.listServers()
            async let volumesTask = client.listVolumes()
            async let primaryIPsTask = client.listPrimaryIPs()
            async let floatingIPsTask = client.listFloatingIPs()
            async let loadBalancersTask = client.listLoadBalancers()

            let servers = try await serversTask
            let volumes = try await volumesTask
            let primaryIPs = try await primaryIPsTask
            let floatingIPs = try await floatingIPsTask
            let loadBalancers = try await loadBalancersTask

            let pricing: Pricing
            var freshPricing: Pricing?
            if let cached = target.cachedPricing {
                pricing = cached
            } else {
                let fetched = try await client.pricing()
                pricing = fetched
                freshPricing = fetched
            }

            var items: [CostItem] = []
            items.append(contentsOf: CostItemBuilder.items(servers: servers, pricing: pricing))
            items.append(contentsOf: CostItemBuilder.items(volumes: volumes, pricing: pricing))
            items.append(contentsOf: CostItemBuilder.items(primaryIPs: primaryIPs, pricing: pricing))
            items.append(contentsOf: CostItemBuilder.items(loadBalancers: loadBalancers, pricing: pricing))
            items.append(contentsOf: floatingIPCostItems(floatingIPs, pricing: pricing))

            return ProjectFetch(
                projectID: target.projectID, projectName: target.projectName,
                items: items, currency: pricing.currency, freshPricing: freshPricing,
                errorMessage: nil
            )
        } catch let apiError as HetznerAPIError {
            return ProjectFetch(
                projectID: target.projectID, projectName: target.projectName,
                items: [], currency: nil, freshPricing: nil, errorMessage: apiError.userMessage
            )
        } catch {
            return ProjectFetch(
                projectID: target.projectID, projectName: target.projectName,
                items: [], currency: nil, freshPricing: nil,
                errorMessage: "Couldn't reach Hetzner right now. Check your connection and try again."
            )
        }
    }

    /// Adapts Floating IPs into `CostItem`s. Hetzner's `/pricing` response
    /// models a Floating IP's price identically to a Primary IP's
    /// (`{type, prices: [{location, price_hourly, price_monthly}]}`), but
    /// `CostItemBuilder` (package-owned, Wave A) doesn't expose a
    /// `floatingIPs` overload — this stays local to the Costs feature,
    /// mirroring `CostItemBuilder`'s own primary-IP matching logic, rather
    /// than editing a file outside this worker's ownership.
    private static func floatingIPCostItems(_ floatingIPs: [FloatingIP], pricing: Pricing) -> [CostItem] {
        floatingIPs.compactMap { floatingIP in
            let candidatePrices = pricing.primaryIPs.first { $0.type == floatingIP.type.rawValue }?.prices
            guard let candidatePrices, !candidatePrices.isEmpty else { return nil }
            let matched = candidatePrices.first { $0.location == floatingIP.homeLocation.name } ?? candidatePrices.first
            guard let monthlyNet = matched?.monthly.netDecimal else { return nil }
            return CostItem(
                id: "floating-ip-\(floatingIP.id)",
                name: floatingIP.name,
                kind: .floatingIP,
                pricing: .monthlyFlat(net: monthlyNet),
                createdAt: floatingIP.created
            )
        }
    }

    // MARK: - Reduce

    private func recompute(manualEntries: [ManualCostEntry], fetches: [ProjectFetch], now: Date, calendar: Calendar) {
        var resolvedCurrency = currency
        var sections: [ProjectSection] = []
        var allItems: [CostItem] = []

        for fetch in fetches {
            if let fetchCurrency = fetch.currency {
                resolvedCurrency = fetchCurrency
            }
            guard !fetch.items.isEmpty else {
                sections.append(
                    ProjectSection(
                        projectID: fetch.projectID, projectName: fetch.projectName,
                        itemCosts: [], projectedTotal: 0, monthToDate: 0,
                        errorMessage: fetch.errorMessage
                    )
                )
                continue
            }

            let summary = CostEngine.summary(
                items: fetch.items, now: now, calendar: calendar,
                currency: fetch.currency ?? resolvedCurrency
            )
            sections.append(
                ProjectSection(
                    projectID: fetch.projectID, projectName: fetch.projectName,
                    itemCosts: summary.perItem, projectedTotal: summary.projectedMonthTotal,
                    monthToDate: summary.monthToDate, errorMessage: fetch.errorMessage
                )
            )
            allItems.append(contentsOf: fetch.items)
        }

        allItems.append(contentsOf: manualEntries.map(\.costItem))
        projectSections = sections.sorted { $0.projectedTotal > $1.projectedTotal }
        monthElapsedFraction = Self.monthElapsedFraction(now: now, calendar: calendar)

        guard !allItems.isEmpty else {
            combinedMonthToDate = nil
            combinedProjected = nil
            kindShares = []
            return
        }

        let combined = CostEngine.summary(items: allItems, now: now, calendar: calendar, currency: resolvedCurrency)
        combinedMonthToDate = combined.monthToDate
        combinedProjected = combined.projectedMonthTotal
        currency = combined.currency
        kindShares = Dictionary(grouping: combined.perItem, by: \.kind)
            .map { kind, items in KindShare(kind: kind, projected: items.reduce(0) { $0 + $1.projectedMonth }) }
            .sorted { $0.projected > $1.projected }
    }

    private static func monthElapsedFraction(now: Date, calendar: Calendar) -> Double {
        guard let interval = calendar.dateInterval(of: .month, for: now) else { return 0 }
        let total = interval.end.timeIntervalSince(interval.start)
        guard total > 0 else { return 0 }
        let elapsed = now.timeIntervalSince(interval.start)
        return min(max(elapsed / total, 0), 1)
    }
}
