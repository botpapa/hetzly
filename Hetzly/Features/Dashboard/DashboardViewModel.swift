import Foundation
import HetznerKit
import Observation

/// Drives the Dashboard: aggregates servers across every project, keeps a
/// stale-while-revalidate cache via `SnapshotStore`, computes the monthly
/// cost burn, and lazily fetches per-server CPU sparklines after the list
/// has already rendered.
///
/// ## Stale-while-revalidate
/// `load(container:)` first paints from `SnapshotStore.loadServers` (marking
/// each project's rows `isStale = true`), then kicks off a live
/// `CloudClient.listServers()` per project concurrently. As each project's
/// live fetch resolves, its section is updated in place, `isStale` clears,
/// and the fresh list is written back to `SnapshotStore`. A project whose
/// live fetch fails keeps showing its last-known (possibly stale) rows plus
/// an inline error message — it never blocks or hides the other projects.
@MainActor
@Observable
final class DashboardViewModel {
    struct ProjectSection: Identifiable, Sendable {
        let projectID: UUID
        var projectName: String
        var servers: [ServerListItem]
        var isStale: Bool
        var errorMessage: String?

        var id: UUID { projectID }
    }

    enum FreshnessBanner: Equatable {
        case none
        case refreshingCache
        case offlineCache
    }

    private(set) var projectSections: [ProjectSection] = []
    private(set) var attention: [ServerListItem] = []
    private(set) var cpuSparklines: [String: [Double]] = [:]
    private(set) var lastRefreshed: Date?
    private(set) var isLoading = false
    private(set) var isRefreshing = false

    /// Cost burn, exposed as three plain values per the module contract
    /// rather than the raw `CostSummary` (which also carries a per-item
    /// breakdown the burn card doesn't need).
    private(set) var monthToDate: Decimal?
    private(set) var projected: Decimal?
    private(set) var currency = "EUR"

    /// A Robot dedicated server paired with the account it was loaded from —
    /// the account ID is needed alongside the server number to build a
    /// `RobotServerRoute` for navigation into `DedicatedServerDetailView`.
    struct DedicatedServerItem: Identifiable, Sendable {
        let accountID: UUID
        let server: RobotServer

        var id: String { "\(accountID.uuidString)#\(server.serverNumber)" }
    }

    /// Every Robot dedicated server across every configured Robot account,
    /// flattened. Loaded once per dashboard load/refresh alongside Cloud
    /// projects — no background polling, per the Robot spec's conservative
    /// request budget.
    private(set) var dedicatedServers: [DedicatedServerItem] = []
    /// Set when one or more Robot accounts failed to load; isolated at
    /// fetch time (one bad account doesn't drop another's servers), joined
    /// into a single line since the dashboard shows one inline error row.
    private(set) var dedicatedError: String?

    /// Full `Server` payloads per project, kept alongside the display-only
    /// `ServerListItem` rows so `CostItemBuilder` has everything it needs
    /// (creation date, server-type prices, etc).
    private var serversByProject: [UUID: [Server]] = [:]

    /// Simple per-VM pricing memo (TTL 24h). The Dashboard is inherently a
    /// single-consumer, `@MainActor`-serialized surface, so a plain
    /// dictionary is sufficient here — `ResponseCache` remains available for
    /// call sites that need cross-consumer sharing.
    private var pricingCache: [UUID: (pricing: Pricing, fetchedAt: Date)] = [:]
    private let pricingTTL: TimeInterval = 24 * 60 * 60

    private var sparklineTask: Task<Void, Never>?

    init() {}

    /// Preview/test-only entry point: seeds state directly with no network
    /// or `AppContainer` involved.
    init(
        projectSections: [ProjectSection] = [],
        attention: [ServerListItem] = [],
        monthToDate: Decimal? = nil,
        projected: Decimal? = nil,
        currency: String = "EUR",
        cpuSparklines: [String: [Double]] = [:],
        lastRefreshed: Date? = nil,
        dedicatedServers: [DedicatedServerItem] = [],
        dedicatedError: String? = nil
    ) {
        self.projectSections = projectSections
        self.attention = attention
        self.monthToDate = monthToDate
        self.projected = projected
        self.currency = currency
        self.cpuSparklines = cpuSparklines
        self.lastRefreshed = lastRefreshed
        self.dedicatedServers = dedicatedServers
        self.dedicatedError = dedicatedError
    }

    var isHealthy: Bool {
        attention.isEmpty && !projectSections.contains { $0.errorMessage != nil }
    }

    /// Drives the "Showing cached data — refreshing…" / "Offline — showing
    /// cached data" banner. Only surfaces while there's actually stale data
    /// on screen — a clean first load or a fully-fresh dashboard shows none.
    var freshnessBanner: FreshnessBanner {
        guard projectSections.contains(where: \.isStale) else { return .none }
        if isLoading || isRefreshing { return .refreshingCache }
        return projectSections.contains { $0.errorMessage != nil } ? .offlineCache : .none
    }

    // MARK: - Lifecycle

    func load(container: AppContainer) async {
        isLoading = true
        loadFromSnapshots(container: container)
        async let liveTask: Void = refreshLive(container: container)
        async let dedicatedTask: Void = loadDedicatedServers(container: container)
        _ = await (liveTask, dedicatedTask)
        await loadCostSummary(container: container)
        isLoading = false
        scheduleSparklineLoad(container: container)
        writeWidgetSnapshot()
    }

    /// Pull-to-refresh. Enforces a 0.6s minimum duration so the `.run`
    /// mascot animation has time to read, even when the network round trip
    /// is fast.
    func refresh(container: AppContainer) async {
        isRefreshing = true
        let start = Date()

        async let liveTask: Void = refreshLive(container: container)
        async let dedicatedTask: Void = loadDedicatedServers(container: container)
        _ = await (liveTask, dedicatedTask)
        await loadCostSummary(container: container)
        scheduleSparklineLoad(container: container)
        writeWidgetSnapshot()

        let elapsed = Date().timeIntervalSince(start)
        let minDuration: TimeInterval = 0.6
        if elapsed < minDuration {
            try? await Task.sleep(for: .seconds(minDuration - elapsed))
        }
        isRefreshing = false
    }

    // MARK: - Stale-while-revalidate: snapshot pass

    private func loadFromSnapshots(container: AppContainer) {
        let snapshotStore = container.snapshotStore()
        let projects = container.projectsStore.projects

        projectSections = projects.map { project in
            if let snapshot = snapshotStore.loadServers(projectID: project.id) {
                serversByProject[project.id] = snapshot.servers
                let items = snapshot.servers.map { ServerListItem(projectID: project.id, server: $0) }
                return ProjectSection(
                    projectID: project.id,
                    projectName: project.name,
                    servers: items,
                    isStale: true,
                    errorMessage: nil
                )
            }
            return ProjectSection(
                projectID: project.id,
                projectName: project.name,
                servers: [],
                isStale: false,
                errorMessage: nil
            )
        }
        recomputeAttention()
    }

    // MARK: - Stale-while-revalidate: live pass

    private func refreshLive(container: AppContainer) async {
        struct FetchTarget: Sendable {
            let projectID: UUID
            let client: CloudClient?
        }

        let projects = container.projectsStore.projects

        // A project added after the last snapshot pass won't have a section
        // yet — make sure every project has one before results start coming
        // back.
        for project in projects where !projectSections.contains(where: { $0.projectID == project.id }) {
            projectSections.append(
                ProjectSection(projectID: project.id, projectName: project.name, servers: [], isStale: false, errorMessage: nil)
            )
        }

        let snapshotStore = container.snapshotStore()
        let targets = projects.map { FetchTarget(projectID: $0.id, client: container.cloudClient(for: $0.id)) }

        await withTaskGroup(of: (UUID, Result<[Server], DashboardLoadError>).self) { group in
            for target in targets {
                group.addTask {
                    guard let client = target.client else {
                        return (target.projectID, .failure(.missingToken))
                    }
                    do {
                        let servers = try await client.listServers()
                        return (target.projectID, .success(servers))
                    } catch let apiError as HetznerAPIError {
                        return (target.projectID, .failure(.underlying(apiError.userMessage)))
                    } catch {
                        return (target.projectID, .failure(.underlying(error.localizedDescription)))
                    }
                }
            }

            for await (projectID, result) in group {
                switch result {
                case .success(let servers):
                    snapshotStore.saveServers(servers, projectID: projectID)
                    serversByProject[projectID] = servers
                    updateSection(projectID: projectID) { section in
                        section.servers = servers.map { ServerListItem(projectID: projectID, server: $0) }
                        section.isStale = false
                        section.errorMessage = nil
                    }
                case .failure(let error):
                    // Per-project isolation: leave any cached (possibly
                    // stale) rows exactly as they are, just surface the
                    // inline error alongside them.
                    updateSection(projectID: projectID) { section in
                        section.errorMessage = error.userMessage
                    }
                }
            }
        }

        lastRefreshed = Date()
        recomputeAttention()
    }

    private func updateSection(projectID: UUID, mutate: (inout ProjectSection) -> Void) {
        guard let index = projectSections.firstIndex(where: { $0.projectID == projectID }) else { return }
        mutate(&projectSections[index])
    }

    /// Mirrors the current dashboard state into the widget's App Group
    /// snapshot after every load/refresh completes, so home/lock screen
    /// widgets stay in sync without any polling of their own.
    private func writeWidgetSnapshot() {
        WidgetSnapshotWriter.write(
            projectSections: projectSections,
            cpuSparklines: cpuSparklines,
            monthToDate: monthToDate,
            projected: projected,
            currency: currency
        )
    }

    private func recomputeAttention() {
        attention = projectSections.flatMap { section in
            section.servers.filter { isAttentionStatus($0.status) }
        }
    }

    // MARK: - Cost burn

    private func loadCostSummary(container: AppContainer) async {
        var items: [CostItem] = []
        var resolvedCurrency = currency

        for project in container.projectsStore.projects {
            guard let servers = serversByProject[project.id], !servers.isEmpty else { continue }
            guard let client = container.cloudClient(for: project.id) else { continue }
            guard let projectPricing = await pricing(for: project.id, client: client) else { continue }
            resolvedCurrency = projectPricing.currency
            items.append(contentsOf: CostItemBuilder.items(servers: servers, pricing: projectPricing))
        }

        guard !items.isEmpty else {
            monthToDate = nil
            projected = nil
            return
        }

        let summary = CostEngine.summary(items: items, now: Date(), calendar: .current, currency: resolvedCurrency)
        monthToDate = summary.monthToDate
        projected = summary.projectedMonthTotal
        currency = summary.currency
    }

    // MARK: - Dedicated servers (Robot)

    /// Fetches every configured Robot account's servers concurrently (with
    /// each other and — via `load()`/`refresh()`'s `async let` — with the
    /// Cloud project fetch too), then flattens them into `dedicatedServers`.
    /// A single request per account (`listServers()`); `RobotClient` itself
    /// enforces the serialized queue, conservative budget, and 5-minute
    /// response cache the Robot spec mandates, so there's no polling here —
    /// this only ever runs once per explicit load/refresh.
    private func loadDedicatedServers(container: AppContainer) async {
        struct RobotFetchTarget: Sendable {
            let accountID: UUID
            let client: RobotClient?
        }
        struct RobotFetchResult: Sendable {
            let items: [DedicatedServerItem]
            let errorMessage: String?
        }

        let accounts = container.robotAccountsStore.accounts
        guard !accounts.isEmpty else {
            dedicatedServers = []
            dedicatedError = nil
            return
        }

        let targets = accounts.map { RobotFetchTarget(accountID: $0.id, client: container.robotClient(for: $0.id)) }

        let results = await withTaskGroup(of: RobotFetchResult.self) { group in
            for target in targets {
                group.addTask {
                    guard let client = target.client else {
                        return RobotFetchResult(items: [], errorMessage: "No credentials configured for this Robot account.")
                    }
                    do {
                        let servers = try await client.listServers()
                        let items = servers.map { DedicatedServerItem(accountID: target.accountID, server: $0) }
                        return RobotFetchResult(items: items, errorMessage: nil)
                    } catch let apiError as HetznerAPIError {
                        return RobotFetchResult(items: [], errorMessage: apiError.userMessage)
                    } catch {
                        return RobotFetchResult(items: [], errorMessage: "Couldn't reach Hetzner Robot right now. Check your connection and try again.")
                    }
                }
            }
            var all: [RobotFetchResult] = []
            all.reserveCapacity(targets.count)
            for await result in group {
                all.append(result)
            }
            return all
        }

        dedicatedServers = results.flatMap(\.items).sorted { $0.server.serverName < $1.server.serverName }
        let errors = results.compactMap(\.errorMessage)
        dedicatedError = errors.isEmpty ? nil : errors.joined(separator: " ")
    }

    private func pricing(for projectID: UUID, client: CloudClient) async -> Pricing? {
        if let cached = pricingCache[projectID], Date().timeIntervalSince(cached.fetchedAt) < pricingTTL {
            return cached.pricing
        }
        do {
            let fetched = try await client.pricing()
            pricingCache[projectID] = (fetched, Date())
            return fetched
        } catch {
            // Fall back to a stale cached price rather than dropping this
            // project's cost contribution entirely.
            return pricingCache[projectID]?.pricing
        }
    }

    // MARK: - CPU sparklines (lazy, fetched after the list already rendered)

    private func scheduleSparklineLoad(container: AppContainer) {
        sparklineTask?.cancel()
        sparklineTask = Task { [weak self] in
            await self?.loadSparklines(container: container)
        }
    }

    private func loadSparklines(container: AppContainer) async {
        struct MetricsTarget: Sendable {
            let key: String
            let serverID: Int
            let client: CloudClient
        }

        let end = Date()
        let start = end.addingTimeInterval(-3600)

        var targets: [MetricsTarget] = []
        for project in container.projectsStore.projects {
            guard let client = container.cloudClient(for: project.id) else { continue }
            let items = projectSections.first(where: { $0.projectID == project.id })?.servers ?? []
            for item in items {
                targets.append(MetricsTarget(key: item.id, serverID: item.serverID, client: client))
            }
        }

        guard !targets.isEmpty else { return }

        await withTaskGroup(of: (String, [Double]?).self) { group in
            for target in targets {
                group.addTask {
                    do {
                        let metrics = try await target.client.serverMetrics(
                            serverID: target.serverID,
                            types: [.cpu],
                            start: start,
                            end: end,
                            step: 60
                        )
                        let series = metrics.series.first { $0.name.lowercased().contains("cpu") } ?? metrics.series.first
                        let values = series?.points.map { $0.value }
                        return (target.key, values)
                    } catch {
                        return (target.key, nil)
                    }
                }
            }

            for await (key, values) in group {
                if let values, !values.isEmpty {
                    cpuSparklines[key] = values
                }
            }
        }
    }
}

private enum DashboardLoadError: Error, Sendable {
    case missingToken
    case underlying(String)

    var userMessage: String {
        switch self {
        case .missingToken:
            return "No token configured for this project."
        case .underlying(let message):
            return message
        }
    }
}

// MARK: - Preview fixtures

#if DEBUG
extension DashboardViewModel {
    static var previewHealthy: DashboardViewModel {
        let projectID = UUID()
        return DashboardViewModel(
            projectSections: [
                ProjectSection(
                    projectID: projectID,
                    projectName: "Personal",
                    servers: [
                        ServerListItem(
                            projectID: projectID, serverID: 1, name: "web-01",
                            status: .running, typeName: "cx22", city: "Falkenstein", countryCode: "DE"
                        ),
                        ServerListItem(
                            projectID: projectID, serverID: 2, name: "db-01",
                            status: .running, typeName: "cx32", city: "Falkenstein", countryCode: "DE"
                        ),
                    ],
                    isStale: false,
                    errorMessage: nil
                ),
            ],
            monthToDate: 42.18,
            projected: 96.40,
            currency: "EUR",
            cpuSparklines: [
                "\(projectID.uuidString)#1": [12, 20, 18, 34, 40, 30, 22],
                "\(projectID.uuidString)#2": [5, 8, 6, 9, 12, 10, 7],
            ],
            lastRefreshed: Date()
        )
    }

    static var previewAttention: DashboardViewModel {
        let projectID = UUID()
        let stopping = ServerListItem(
            projectID: projectID, serverID: 3, name: "worker-03",
            status: .stopping, typeName: "cx22", city: "Ashburn", countryCode: "US"
        )
        let running = ServerListItem(
            projectID: projectID, serverID: 4, name: "cache-01",
            status: .running, typeName: "cx22", city: "Ashburn", countryCode: "US"
        )
        return DashboardViewModel(
            projectSections: [
                ProjectSection(projectID: projectID, projectName: "Staging", servers: [stopping, running], isStale: false, errorMessage: nil),
            ],
            attention: [stopping],
            monthToDate: 12.40,
            projected: 28.10,
            currency: "EUR",
            lastRefreshed: Date()
        )
    }

    static var previewStaleOffline: DashboardViewModel {
        let projectID = UUID()
        return DashboardViewModel(
            projectSections: [
                ProjectSection(
                    projectID: projectID,
                    projectName: "Personal",
                    servers: [
                        ServerListItem(
                            projectID: projectID, serverID: 5, name: "web-01",
                            status: .running, typeName: "cx22", city: "Falkenstein", countryCode: "DE"
                        ),
                    ],
                    isStale: true,
                    errorMessage: "A network error occurred. Please check your connection and try again."
                ),
            ],
            monthToDate: 42.18,
            projected: 96.40,
            currency: "EUR",
            lastRefreshed: Date().addingTimeInterval(-3600)
        )
    }

    static var previewEmptyProject: DashboardViewModel {
        let projectID = UUID()
        return DashboardViewModel(
            projectSections: [
                ProjectSection(projectID: projectID, projectName: "Sandbox", servers: [], isStale: false, errorMessage: nil),
            ]
        )
    }
}
#endif
