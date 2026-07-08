import Foundation
import HetznerKit
import Observation

/// Drives `ProjectDetailView`: the per-project command center. Loads every
/// resource category for a single project concurrently — servers (full
/// payload, for the row list and cost math), the billable resources
/// `CostItemBuilder` needs (volumes, primary IPs, floating IPs, load
/// balancers), and count-only categories (networks, firewalls, SSH keys,
/// certificates) — then reduces the billable ones through `CostEngine` for
/// this project's own burn.
///
/// ## Stale-tolerant loading
/// `load(container:)` first paints the server list from
/// `SnapshotStore.loadServers` (marking `isStale = true`) so the screen never
/// opens blank, then kicks off the live fetch. Every sub-load (servers, each
/// resource category, pricing) is isolated from every other: one category
/// failing surfaces inline (via `resourceErrors` or, for servers, a
/// stale/error server section) without blocking or hiding the rest — same
/// per-resource isolation `DashboardViewModel`/`CostsViewModel` use.
@MainActor
@Observable
final class ProjectDetailViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    struct ResourceCounts: Equatable {
        var volumes: Int?
        var networks: Int?
        var firewalls: Int?
        var loadBalancers: Int?
        var primaryIPs: Int?
        var floatingIPs: Int?
        var sshKeys: Int?
        var certificates: Int?
    }

    let projectID: UUID

    private(set) var loadState: LoadState = .idle
    private(set) var isRefreshing = false
    /// Set once a live fetch has failed but a previous (possibly snapshot)
    /// server list is still on screen.
    private(set) var isStale = false

    private(set) var servers: [ServerListItem] = []
    private(set) var counts = ResourceCounts()
    /// Deduplicated, human-readable messages for every resource *category*
    /// (not the server list itself, which drives `loadState`) that failed to
    /// load on the last pass.
    private(set) var resourceErrors: [String] = []

    private(set) var monthToDate: Decimal?
    private(set) var projected: Decimal?
    private(set) var currency = "EUR"
    private(set) var topCostItems: [CostSummary.ItemCost] = []

    /// True once we know for certain this project has no stored token —
    /// distinct from a transient network failure, since pull-to-refresh
    /// can't fix it; only "Update API token" in the Manage section can.
    private(set) var missingToken = false

    init(projectID: UUID) {
        self.projectID = projectID
    }

    /// Preview/test-only entry point: seeds state directly, no network or
    /// `AppContainer` involved.
    init(
        projectID: UUID,
        servers: [ServerListItem] = [],
        counts: ResourceCounts = ResourceCounts(),
        resourceErrors: [String] = [],
        monthToDate: Decimal? = nil,
        projected: Decimal? = nil,
        currency: String = "EUR",
        topCostItems: [CostSummary.ItemCost] = [],
        loadState: LoadState = .loaded,
        isStale: Bool = false,
        missingToken: Bool = false
    ) {
        self.projectID = projectID
        self.servers = servers
        self.counts = counts
        self.resourceErrors = resourceErrors
        self.monthToDate = monthToDate
        self.projected = projected
        self.currency = currency
        self.topCostItems = topCostItems
        self.loadState = loadState
        self.isStale = isStale
        self.missingToken = missingToken
    }

    // MARK: - Lifecycle

    func load(container: AppContainer) async {
        loadFromSnapshot(container: container)
        if servers.isEmpty {
            loadState = .loading
        }
        await refresh(container: container)
    }

    /// Pull-to-refresh, and the entry point `load(container:)` itself calls
    /// after painting from the snapshot.
    func refresh(container: AppContainer) async {
        isRefreshing = true
        defer { isRefreshing = false }

        guard let client = container.cloudClient(for: projectID) else {
            missingToken = true
            loadState = servers.isEmpty ? .failed("No token configured for this project.") : .loaded
            isStale = !servers.isEmpty
            counts = ResourceCounts()
            resourceErrors = []
            monthToDate = nil
            projected = nil
            topCostItems = []
            return
        }
        missingToken = false

        async let serversFetch = Self.fetchList { try await client.listServers() }
        async let volumesFetch = Self.fetchList { try await client.listVolumes() }
        async let primaryIPsFetch = Self.fetchList { try await client.listPrimaryIPs() }
        async let floatingIPsFetch = Self.fetchList { try await client.listFloatingIPs() }
        async let loadBalancersFetch = Self.fetchList { try await client.listLoadBalancers() }
        async let firewallsFetch = Self.fetchList { try await client.listFirewalls() }
        async let networksFetch = Self.fetchList { try await client.listNetworks() }
        async let sshKeysFetch = Self.fetchList { try await client.listSSHKeys() }
        async let certificatesFetch = Self.fetchList { try await client.listCertificates() }
        async let pricingFetch: Pricing? = try? await client.pricing()

        let (
            serversResult, volumesResult, primaryIPsResult, floatingIPsResult, loadBalancersResult,
            firewallsResult, networksResult, sshKeysResult, certificatesResult, pricing
        ) = await (
            serversFetch, volumesFetch, primaryIPsFetch, floatingIPsFetch, loadBalancersFetch,
            firewallsFetch, networksFetch, sshKeysFetch, certificatesFetch, pricingFetch
        )

        applyServers(serversResult, container: container)

        counts = ResourceCounts(
            volumes: volumesResult.count,
            networks: networksResult.count,
            firewalls: firewallsResult.count,
            loadBalancers: loadBalancersResult.count,
            primaryIPs: primaryIPsResult.count,
            floatingIPs: floatingIPsResult.count,
            sshKeys: sshKeysResult.count,
            certificates: certificatesResult.count
        )

        resourceErrors = [
            volumesResult.errorMessage, primaryIPsResult.errorMessage, floatingIPsResult.errorMessage,
            loadBalancersResult.errorMessage, firewallsResult.errorMessage, networksResult.errorMessage,
            sshKeysResult.errorMessage, certificatesResult.errorMessage,
        ]
        .compactMap { $0 }
        .reduce(into: [String]()) { unique, message in
            if !unique.contains(message) { unique.append(message) }
        }

        applyCosts(
            servers: serversResult.items, volumes: volumesResult.items, primaryIPs: primaryIPsResult.items,
            floatingIPs: floatingIPsResult.items, loadBalancers: loadBalancersResult.items, pricing: pricing
        )
    }

    // MARK: - Snapshot pass

    private func loadFromSnapshot(container: AppContainer) {
        guard servers.isEmpty, let snapshot = container.snapshotStore().loadServers(projectID: projectID) else { return }
        servers = snapshot.servers.map { ServerListItem(projectID: projectID, server: $0) }
        isStale = true
        loadState = .loaded
    }

    // MARK: - Applying results

    private func applyServers(_ result: CategoryFetch<Server>, container: AppContainer) {
        if let errorMessage = result.errorMessage {
            if servers.isEmpty {
                loadState = .failed(errorMessage)
            } else {
                // Per-project isolation, mirroring `DashboardViewModel`: keep
                // whatever rows are already on screen (live or stale
                // snapshot) rather than clearing them on a failed refresh.
                loadState = .loaded
                isStale = true
            }
            return
        }
        container.snapshotStore().saveServers(result.items, projectID: projectID)
        servers = result.items.map { ServerListItem(projectID: projectID, server: $0) }
        isStale = false
        loadState = .loaded
    }

    private func applyCosts(
        servers: [Server], volumes: [Volume], primaryIPs: [PrimaryIP],
        floatingIPs: [FloatingIP], loadBalancers: [LoadBalancer], pricing: Pricing?
    ) {
        guard let pricing else {
            // Pricing failed to load this pass — leave the previous burn
            // figures on screen rather than blanking them.
            return
        }

        var items: [CostItem] = []
        items.append(contentsOf: CostItemBuilder.items(servers: servers, pricing: pricing))
        items.append(contentsOf: CostItemBuilder.items(volumes: volumes, pricing: pricing))
        items.append(contentsOf: CostItemBuilder.items(primaryIPs: primaryIPs, pricing: pricing))
        items.append(contentsOf: CostItemBuilder.items(loadBalancers: loadBalancers, pricing: pricing))
        items.append(contentsOf: Self.floatingIPCostItems(floatingIPs, pricing: pricing))

        guard !items.isEmpty else {
            monthToDate = nil
            projected = nil
            topCostItems = []
            return
        }

        let summary = CostEngine.summary(items: items, now: Date(), calendar: .current, currency: pricing.currency)
        monthToDate = summary.monthToDate
        projected = summary.projectedMonthTotal
        currency = summary.currency
        topCostItems = Array(summary.perItem.prefix(5))
    }

    // MARK: - Fetch helpers

    private struct CategoryFetch<T: Sendable>: Sendable {
        var items: [T] = []
        var errorMessage: String?

        var count: Int? { errorMessage == nil ? items.count : nil }
    }

    private static func fetchList<T: Sendable>(_ operation: @Sendable () async throws -> [T]) async -> CategoryFetch<T> {
        do {
            return CategoryFetch(items: try await operation())
        } catch let apiError as HetznerAPIError {
            return CategoryFetch(errorMessage: apiError.userMessage)
        } catch {
            return CategoryFetch(errorMessage: "Couldn't reach Hetzner right now. Check your connection and try again.")
        }
    }

    /// Adapts Floating IPs into `CostItem`s, mirroring `CostsViewModel`'s own
    /// private helper of the same name — `CostItemBuilder` (package-owned,
    /// outside this worker's scope) doesn't expose a `floatingIPs` overload.
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
}
