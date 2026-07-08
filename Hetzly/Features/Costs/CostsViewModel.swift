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
        /// `true` when `errorMessage` came from `HetznerAPIError.unauthorized`
        /// — drives `CostProjectSectionView`'s "Update token…" affordance.
        /// Defaulted so existing `errorMessage:`-only call sites (previews)
        /// keep compiling unchanged.
        var isAuthError = false

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

        /// This project's own kind breakdown, shaped for `CostKindDonutChart`
        /// — used when Costs is scoped to a single project via
        /// `ProjectFilterBar`, mirroring the combined `kindShares` the donut
        /// shows in the "All" view.
        var kindShares: [KindShare] {
            kindSubtotals.map { KindShare(kind: $0.kind, projected: $0.projectedTotal) }
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

    /// One Robot dedicated server, flattened across every configured Robot
    /// account. `monthlyPrice`/`note` come from `DedicatedPriceStore`; `nil`
    /// price means the server hasn't been priced yet — it's still listed
    /// (so users see it and can price it) but excluded from every total
    /// until it is, since Robot has no pricing API for servers you already
    /// own.
    struct DedicatedServerRow: Identifiable, Sendable, Equatable {
        let accountID: UUID
        let serverNumber: Int
        let name: String
        let product: String
        let datacenter: String
        let ip: String?
        let status: RobotServerStatus
        let cancelled: Bool
        let monthlyPrice: Decimal?
        let note: String?

        var id: String { "dedicated-\(accountID.uuidString)-\(serverNumber)" }
    }

    private(set) var projectSections: [ProjectSection] = []
    private(set) var combinedMonthToDate: Decimal?
    private(set) var combinedProjected: Decimal?
    private(set) var currency = "EUR"
    private(set) var kindShares: [KindShare] = []
    private(set) var monthElapsedFraction: Double = 0
    private(set) var isLoading = false
    private(set) var isRefreshing = false

    /// Every Robot server across every configured account, regardless of
    /// whether it's been priced yet.
    private(set) var dedicatedServers: [DedicatedServerRow] = []
    /// Combined message when one or more Robot accounts failed to load —
    /// isolated per account at fetch time (one bad account never drops the
    /// others), joined into a single line for display since Costs shows one
    /// dedicated-servers section, not one per account.
    private(set) var dedicatedErrorMessage: String?
    /// `true` when at least one of the failed Robot accounts above failed on
    /// bad credentials specifically — `DedicatedCostSection` uses this to
    /// show the "update the account in Settings" hint rather than a bare
    /// error, mirroring `DedicatedListViewModel`'s Robot-side recovery copy.
    private(set) var dedicatedIsAuthError = false

    /// Cloud server "what I pay" overrides currently in effect, keyed by
    /// `Server.id` — the same dict handed to
    /// `CostItemBuilder.items(servers:pricing:overrides:)` for every
    /// project's fetch this pass. Exposed so `CostProjectSectionView` can
    /// tell, per row, whether a server's price is a user override or
    /// Hetzner's list price (the "custom" chip).
    private(set) var cloudServerOverrides: [Int: Decimal] = [:]

    /// Hetzner's current list-price monthly equivalent for every Cloud
    /// server across every project, keyed by `Server.id` — computed
    /// alongside `cloudServerOverrides` regardless of whether a server has
    /// an override, so `CloudServerPriceSheet` can show "List price: €X" as
    /// a hint even while editing an existing override.
    private(set) var cloudServerListPrices: [Int: Decimal] = [:]

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
        monthElapsedFraction: Double = 0,
        dedicatedServers: [DedicatedServerRow] = [],
        dedicatedErrorMessage: String? = nil,
        cloudServerOverrides: [Int: Decimal] = [:],
        cloudServerListPrices: [Int: Decimal] = [:]
    ) {
        self.projectSections = projectSections
        self.combinedMonthToDate = combinedMonthToDate
        self.combinedProjected = combinedProjected
        self.currency = currency
        self.kindShares = kindShares
        self.monthElapsedFraction = monthElapsedFraction
        self.dedicatedServers = dedicatedServers
        self.dedicatedErrorMessage = dedicatedErrorMessage
        self.cloudServerOverrides = cloudServerOverrides
        self.cloudServerListPrices = cloudServerListPrices
    }

    /// True once we know for certain there is nothing to show: no project
    /// has any billable resource, and there are no manual entries either.
    var isEmpty: Bool {
        combinedProjected == nil
    }

    /// Hero numbers scoped to a single project (or the combined totals when
    /// `projectID` is `nil`, i.e. the "All" view). Reuses each project's
    /// already-computed `ProjectSection` — no extra fetch or math, just a
    /// lookup — so `CostsView` can drive `CostsHeroCard` from whatever the
    /// `ProjectFilterBar` selection is.
    func heroSummary(forProjectID projectID: UUID?) -> (monthToDate: Decimal?, projected: Decimal?) {
        guard let projectID else {
            return (combinedMonthToDate, combinedProjected)
        }
        guard let section = projectSections.first(where: { $0.projectID == projectID }) else {
            return (nil, nil)
        }
        return (section.monthToDate, section.projectedTotal)
    }

    // MARK: - Lifecycle

    func load(
        container: AppContainer, manualEntries: [ManualCostEntry], dedicatedPrices: [DedicatedPriceEntry],
        cloudServerPrices: [CloudServerPriceEntry] = []
    ) async {
        isLoading = true
        await refresh(container: container, manualEntries: manualEntries, dedicatedPrices: dedicatedPrices, cloudServerPrices: cloudServerPrices)
        isLoading = false
    }

    func refresh(
        container: AppContainer, manualEntries: [ManualCostEntry], dedicatedPrices: [DedicatedPriceEntry],
        cloudServerPrices: [CloudServerPriceEntry] = []
    ) async {
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

        // Cloud server "what I pay" overrides — a single flat dict applied
        // across every project's fetch, keyed by `Server.id`. Not scoped per
        // project, mirroring `applyRobotFetches`'s own flat
        // `priceByServerNumber` lookup below: Hetzner Cloud server ids are
        // unique across the whole platform, not just within one project.
        let overrides = Dictionary(uniqueKeysWithValues: cloudServerPrices.map { ($0.serverNumber, $0.monthlyPrice) })
        cloudServerOverrides = overrides

        // Cloud projects and Robot accounts are fetched concurrently with
        // each other (not just internally) — neither waits on the other.
        async let fetchesTask = Self.fetchAllProjects(targets, overrides: overrides)
        async let robotFetchesTask = Self.fetchAllRobotAccounts(container: container)
        let fetches = await fetchesTask
        let robotFetches = await robotFetchesTask

        for fetch in fetches {
            if let freshPricing = fetch.freshPricing {
                pricingCache[fetch.projectID] = (freshPricing, now)
            }
        }

        var listPrices: [Int: Decimal] = [:]
        for fetch in fetches {
            listPrices.merge(fetch.cloudServerListPrices) { _, new in new }
        }
        cloudServerListPrices = listPrices

        let priceByServerNumber = Dictionary(uniqueKeysWithValues: dedicatedPrices.map { ($0.serverNumber, $0) })
        applyRobotFetches(robotFetches, priceByServerNumber: priceByServerNumber)

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
        /// Hetzner's list-price monthly equivalent for every Cloud server in
        /// this project, keyed by `Server.id` — computed independent of any
        /// override, purely for `CloudServerPriceSheet`'s "List price: €X"
        /// hint. Empty on a failed fetch (no servers means nothing to key).
        let cloudServerListPrices: [Int: Decimal]
        let error: DisplayableError?
    }

    /// Fetches every project concurrently with every other project.
    private static func fetchAllProjects(_ targets: [FetchTarget], overrides: [Int: Decimal]) async -> [ProjectFetch] {
        guard !targets.isEmpty else { return [] }
        return await withTaskGroup(of: ProjectFetch.self) { group in
            for target in targets {
                group.addTask { await Self.fetchProject(target, overrides: overrides) }
            }
            var results: [ProjectFetch] = []
            results.reserveCapacity(targets.count)
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    /// Fetches one project's five resource lists (concurrently) plus
    /// pricing, then adapts everything into `CostItem`s. Never throws out to
    /// the caller: any failure becomes this project's isolated
    /// `errorMessage` instead.
    private static func fetchProject(_ target: FetchTarget, overrides: [Int: Decimal]) async -> ProjectFetch {
        guard let client = target.client else {
            return ProjectFetch(
                projectID: target.projectID, projectName: target.projectName,
                items: [], currency: nil, freshPricing: nil, cloudServerListPrices: [:],
                error: DisplayableError(message: "No token configured for this project.")
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
            items.append(contentsOf: CostItemBuilder.items(servers: servers, pricing: pricing, overrides: overrides))
            items.append(contentsOf: CostItemBuilder.items(volumes: volumes, pricing: pricing))
            items.append(contentsOf: CostItemBuilder.items(primaryIPs: primaryIPs, pricing: pricing))
            items.append(contentsOf: CostItemBuilder.items(loadBalancers: loadBalancers, pricing: pricing))
            items.append(contentsOf: floatingIPCostItems(floatingIPs, pricing: pricing))

            // List-price lookup for the sheet's hint — computed
            // independently of `overrides` (i.e. always Hetzner's current
            // list price), even for a server that already has an override.
            let listItems = CostItemBuilder.items(servers: servers, pricing: pricing)
            let listPrices = Self.cloudServerListPrices(from: listItems)

            return ProjectFetch(
                projectID: target.projectID, projectName: target.projectName,
                items: items, currency: pricing.currency, freshPricing: freshPricing,
                cloudServerListPrices: listPrices, error: nil
            )
        } catch let apiError as HetznerAPIError {
            return ProjectFetch(
                projectID: target.projectID, projectName: target.projectName,
                items: [], currency: nil, freshPricing: nil, cloudServerListPrices: [:],
                error: DisplayableError(apiError)
            )
        } catch {
            return ProjectFetch(
                projectID: target.projectID, projectName: target.projectName,
                items: [], currency: nil, freshPricing: nil, cloudServerListPrices: [:],
                error: DisplayableError(message: "Couldn't reach Hetzner right now. Check your connection and try again.")
            )
        }
    }

    /// Extracts `Server.id → list monthly price` from a set of un-overridden
    /// `CostItem`s built by `CostItemBuilder`, parsing back the `"server-<id>"`
    /// id scheme that builder uses. `.hourly` items use their `monthlyCap`
    /// (Hetzner's own advertised monthly-equivalent price); `.monthlyFlat`
    /// is handled too even though a plain (no-override) server item is
    /// always `.hourly` today, so this stays correct if that ever changes.
    private static func cloudServerListPrices(from items: [CostItem]) -> [Int: Decimal] {
        var result: [Int: Decimal] = [:]
        for item in items where item.kind == .server {
            guard item.id.hasPrefix("server-"), let serverID = Int(item.id.dropFirst("server-".count)) else { continue }
            switch item.pricing {
            case .hourly(_, let monthlyCap):
                if let monthlyCap { result[serverID] = monthlyCap }
            case .monthlyFlat(let net):
                result[serverID] = net
            }
        }
        return result
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

    // MARK: - Robot dedicated servers

    private struct RobotAccountFetchTarget: Sendable {
        let accountID: UUID
        let client: RobotClient?
    }

    private struct RobotAccountFetch: Sendable {
        let accountID: UUID
        let servers: [RobotServer]
        let error: DisplayableError?
    }

    /// Fetches every Robot account concurrently with every other account
    /// (and, at the `refresh` call site, concurrently with every Cloud
    /// project too). A single request per account (`listServers()`) —
    /// `RobotClient` itself enforces the spec-mandated serialized queue,
    /// conservative budget, and 5-minute response cache, so calling this
    /// again shortly after (e.g. right after the user edits a price
    /// locally) is effectively free.
    private static func fetchAllRobotAccounts(container: AppContainer) async -> [RobotAccountFetch] {
        let accounts = container.robotAccountsStore.accounts
        guard !accounts.isEmpty else { return [] }

        let targets = accounts.map { RobotAccountFetchTarget(accountID: $0.id, client: container.robotClient(for: $0.id)) }
        return await withTaskGroup(of: RobotAccountFetch.self) { group in
            for target in targets {
                group.addTask { await Self.fetchRobotAccount(target) }
            }
            var results: [RobotAccountFetch] = []
            results.reserveCapacity(targets.count)
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    /// Never throws out to the caller: any failure becomes this account's
    /// isolated `errorMessage` instead, exactly like `fetchProject`.
    private static func fetchRobotAccount(_ target: RobotAccountFetchTarget) async -> RobotAccountFetch {
        guard let client = target.client else {
            return RobotAccountFetch(
                accountID: target.accountID, servers: [],
                error: DisplayableError(message: "No credentials configured for this Robot account.")
            )
        }

        do {
            let servers = try await client.listServers()
            return RobotAccountFetch(accountID: target.accountID, servers: servers, error: nil)
        } catch let apiError as HetznerAPIError {
            return RobotAccountFetch(accountID: target.accountID, servers: [], error: DisplayableError(apiError))
        } catch {
            return RobotAccountFetch(
                accountID: target.accountID, servers: [],
                error: DisplayableError(message: "Couldn't reach Hetzner Robot right now. Check your connection and try again.")
            )
        }
    }

    /// Flattens every account's servers into `dedicatedServers`, attaching
    /// each one's manually entered price (if any) from `DedicatedPriceStore`.
    /// A server without a set price stays in the list (as a "Set price" row
    /// in the UI) — it just never produces a `CostItem`, so it's excluded
    /// from every total until priced.
    private func applyRobotFetches(_ robotFetches: [RobotAccountFetch], priceByServerNumber: [Int: DedicatedPriceEntry]) {
        var rows: [DedicatedServerRow] = []
        var errors: [String] = []
        var isAuthError = false

        for fetch in robotFetches {
            if let error = fetch.error {
                errors.append(error.message)
                isAuthError = isAuthError || error.isAuthError
            }
            for server in fetch.servers {
                let priceEntry = priceByServerNumber[server.serverNumber]
                rows.append(
                    DedicatedServerRow(
                        accountID: fetch.accountID,
                        serverNumber: server.serverNumber,
                        name: server.serverName,
                        product: server.product,
                        datacenter: server.dc,
                        ip: server.serverIP,
                        status: server.status,
                        cancelled: server.cancelled,
                        monthlyPrice: priceEntry?.monthlyPrice,
                        note: priceEntry?.note
                    )
                )
            }
        }

        dedicatedServers = rows.sorted { $0.name < $1.name }
        dedicatedErrorMessage = errors.isEmpty ? nil : errors.joined(separator: " ")
        dedicatedIsAuthError = isAuthError
    }

    /// Priced dedicated servers, adapted into `CostItem`s the same way
    /// `ManualCostEntry.costItem` is — these feed the combined summary and
    /// donut alongside every project's live inventory, but (like manual
    /// entries) never into any per-project `ProjectSection`, since Robot
    /// accounts aren't Cloud projects.
    private var dedicatedCostItems: [CostItem] {
        dedicatedServers.compactMap { row in
            guard let price = row.monthlyPrice else { return nil }
            return CostItem(id: row.id, name: row.name, kind: .dedicated, pricing: .monthlyFlat(net: price), createdAt: nil)
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
                        errorMessage: fetch.error?.message,
                        isAuthError: fetch.error?.isAuthError ?? false
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
                    monthToDate: summary.monthToDate, errorMessage: fetch.error?.message,
                    isAuthError: fetch.error?.isAuthError ?? false
                )
            )
            allItems.append(contentsOf: fetch.items)
        }

        allItems.append(contentsOf: manualEntries.map(\.costItem))
        allItems.append(contentsOf: dedicatedCostItems)
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
