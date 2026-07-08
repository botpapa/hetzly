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
        /// `true` when `errorMessage` came from `HetznerAPIError.unauthorized`
        /// — the recoverable case an "Update token…" affordance can actually
        /// fix. Defaulted so every existing `errorMessage:`-only call site
        /// (previews, tests) keeps compiling unchanged.
        var isAuthError = false

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

    /// Per-project cost burn, computed alongside the combined totals above so
    /// the burn card can scope to a single project when the dashboard's
    /// `ProjectFilterBar` selection isn't "All". Additive to the combined
    /// figures — never consulted by `writeWidgetSnapshot()`, which always
    /// mirrors the unfiltered combined totals (widgets show everything).
    private(set) var perProjectBurn: [UUID: (monthToDate: Decimal, projected: Decimal)] = [:]

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
    /// `true` when at least one of the failed Robot accounts above failed on
    /// bad credentials specifically — `DedicatedSectionView` uses this to
    /// point at Settings → Robot Accounts instead of a bare error, since
    /// Robot has no `UpdateTokenSheet`-style in-place recovery.
    private(set) var dedicatedIsAuthError = false

    /// `ServerListItem.id`s with a row quick action (from the dashboard's
    /// `.contextMenu`) currently in flight — driving the unobtrusive in-row
    /// spinner overlay. A `Set` rather than a per-item progress value: the
    /// row UI only needs "busy or not", and multiple rows can be busy at
    /// once (independent per-server actions, no cross-row locking).
    private(set) var rowActionInFlight: Set<String> = []

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
        dedicatedError: String? = nil,
        perProjectBurn: [UUID: (monthToDate: Decimal, projected: Decimal)] = [:]
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
        self.perProjectBurn = perProjectBurn
    }

    var isHealthy: Bool {
        attention.isEmpty && !projectSections.contains { $0.errorMessage != nil }
    }

    /// Cost burn scoped to a single project, or the combined totals when
    /// `projectID` is `nil` ("All"). Falls back to `(nil, nil)` for a project
    /// that has no cost items yet (e.g. still loading, or has zero servers).
    func burn(for projectID: UUID?) -> (monthToDate: Decimal?, projected: Decimal?) {
        guard let projectID else {
            return (monthToDate, projected)
        }
        guard let value = perProjectBurn[projectID] else {
            return (nil, nil)
        }
        return (value.monthToDate, value.projected)
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
                        return (target.projectID, .failure(.underlying(DisplayableError(apiError))))
                    } catch {
                        return (target.projectID, .failure(.underlying(DisplayableError(message: error.localizedDescription))))
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
                        section.isAuthError = false
                    }
                case .failure(let error):
                    // Per-project isolation: leave any cached (possibly
                    // stale) rows exactly as they are, just surface the
                    // inline error alongside them.
                    updateSection(projectID: projectID) { section in
                        section.errorMessage = error.userMessage.message
                        section.isAuthError = error.userMessage.isAuthError
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
        var itemsByProject: [UUID: [CostItem]] = [:]
        var resolvedCurrency = currency

        for project in container.projectsStore.projects {
            guard let servers = serversByProject[project.id], !servers.isEmpty else { continue }
            guard let client = container.cloudClient(for: project.id) else { continue }
            guard let projectPricing = await pricing(for: project.id, client: client) else { continue }
            resolvedCurrency = projectPricing.currency
            let projectItems = CostItemBuilder.items(servers: servers, pricing: projectPricing)
            items.append(contentsOf: projectItems)
            itemsByProject[project.id] = projectItems
        }

        guard !items.isEmpty else {
            monthToDate = nil
            projected = nil
            perProjectBurn = [:]
            return
        }

        let summary = CostEngine.summary(items: items, now: Date(), calendar: .current, currency: resolvedCurrency)
        monthToDate = summary.monthToDate
        projected = summary.projectedMonthTotal
        currency = summary.currency

        var perProject: [UUID: (monthToDate: Decimal, projected: Decimal)] = [:]
        for (projectID, projectItems) in itemsByProject {
            let projectSummary = CostEngine.summary(items: projectItems, now: Date(), calendar: .current, currency: resolvedCurrency)
            perProject[projectID] = (monthToDate: projectSummary.monthToDate, projected: projectSummary.projectedMonthTotal)
        }
        perProjectBurn = perProject
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
            let error: DisplayableError?
        }

        let accounts = container.robotAccountsStore.accounts
        guard !accounts.isEmpty else {
            dedicatedServers = []
            dedicatedError = nil
            dedicatedIsAuthError = false
            return
        }

        let targets = accounts.map { RobotFetchTarget(accountID: $0.id, client: container.robotClient(for: $0.id)) }

        let results = await withTaskGroup(of: RobotFetchResult.self) { group in
            for target in targets {
                group.addTask {
                    guard let client = target.client else {
                        return RobotFetchResult(items: [], error: DisplayableError(message: "No credentials configured for this Robot account."))
                    }
                    do {
                        let servers = try await client.listServers()
                        let items = servers.map { DedicatedServerItem(accountID: target.accountID, server: $0) }
                        return RobotFetchResult(items: items, error: nil)
                    } catch let apiError as HetznerAPIError {
                        return RobotFetchResult(items: [], error: DisplayableError(apiError))
                    } catch {
                        return RobotFetchResult(items: [], error: DisplayableError(message: "Couldn't reach Hetzner Robot right now. Check your connection and try again."))
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
        let errors = results.compactMap(\.error)
        dedicatedError = errors.isEmpty ? nil : errors.map(\.message).joined(separator: " ")
        dedicatedIsAuthError = errors.contains { $0.isAuthError }
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

        // Collected into a plain local dictionary and merged into
        // `cpuSparklines` (the @Observable-tracked property) exactly once
        // at the end, rather than once per server as each fetch resolves.
        // Assigning per-server here would invalidate every row's identity
        // repeatedly in the seconds right after a load/refresh — exactly
        // when a user is most likely to be tapping a row to navigate in —
        // which was intermittently swallowing that tap. One batched
        // assignment keeps the post-load view stable.
        var collected: [String: [Double]] = [:]
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
                    collected[key] = values
                }
            }
        }

        guard !collected.isEmpty else { return }
        cpuSparklines.merge(collected) { _, new in new }
    }

    // MARK: - Row quick actions (dashboard `.contextMenu`)

    /// Fires a contextual power action from a dashboard row's context menu
    /// directly against `CloudClient` (deliberately not routed through
    /// `ServerDetailViewModel` — the dashboard has no server-detail view
    /// model instance for a row it hasn't navigated into), tracks it to
    /// completion via `ActionTracker`, then refreshes just that one
    /// project's section so the row reflects the new state. Confirmation and
    /// the biometric gate happen in `DashboardView` before this is called;
    /// this method assumes the action has already been approved.
    func performRowAction(_ action: PowerAction, item: ServerListItem, container: AppContainer) async {
        guard let client = container.cloudClient(for: item.projectID) else { return }
        rowActionInFlight.insert(item.id)
        defer { rowActionInFlight.remove(item.id) }

        do {
            let started = try await fireRowAction(action, serverID: item.serverID, client: client)
            let tracker = ActionTracker(client: client)
            // Drain to a terminal update (finished/failed/timedOut); the row
            // spinner is unobtrusive by design, so there's no separate
            // inline error surface here — a failed action just leaves the
            // row showing its last-known (refreshed below) state.
            for await update in await tracker.track(actionID: started.id) {
                if case .progress = update { continue }
                break
            }
        } catch {
            // Same rationale: no dashboard-row inline error UI. The refresh
            // below still runs so the row reflects reality either way.
        }

        await refreshLiveProject(item.projectID, container: container)
    }

    /// Maps the small set of contextual `PowerAction`s the dashboard's row
    /// quick-actions menu offers (reboot/shutdown/power-on) onto their
    /// `CloudClient` calls. Every other `PowerAction` case is Server
    /// Detail-only and never reaches this method.
    private func fireRowAction(_ action: PowerAction, serverID: Int, client: CloudClient) async throws -> Action {
        switch action {
        case .powerOn: try await client.powerOn(serverID: serverID)
        case .shutdown: try await client.shutdown(serverID: serverID)
        case .reboot: try await client.reboot(serverID: serverID)
        case .reset, .powerOff, .delete:
            throw DashboardLoadError.underlying(DisplayableError(message: "Unsupported row action."))
        }
    }

    /// Refetches a single project's live server list and updates just its
    /// `ProjectSection` in place — the scoped counterpart to `refreshLive`'s
    /// all-projects sweep, used after a row quick action so one contextual
    /// tap doesn't re-fetch every other project too.
    private func refreshLiveProject(_ projectID: UUID, container: AppContainer) async {
        guard let client = container.cloudClient(for: projectID) else { return }
        let snapshotStore = container.snapshotStore()
        do {
            let servers = try await client.listServers()
            snapshotStore.saveServers(servers, projectID: projectID)
            serversByProject[projectID] = servers
            updateSection(projectID: projectID) { section in
                section.servers = servers.map { ServerListItem(projectID: projectID, server: $0) }
                section.isStale = false
                section.errorMessage = nil
                section.isAuthError = false
            }
        } catch {
            let displayable = DisplayableError(error)
            updateSection(projectID: projectID) { section in
                section.errorMessage = displayable.message
                section.isAuthError = displayable.isAuthError
            }
        }
        recomputeAttention()
        writeWidgetSnapshot()
    }
}

private enum DashboardLoadError: Error, Sendable {
    case missingToken
    case underlying(DisplayableError)

    var userMessage: DisplayableError {
        switch self {
        case .missingToken:
            return DisplayableError(message: "No token configured for this project.")
        case .underlying(let error):
            return error
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

    /// Multi-project state: three `ProjectSection`s plus a `perProjectBurn`
    /// entry for each, so previews can exercise `ProjectFilterBar` scoping,
    /// section collapse, and the per-project burn card together. Fixed
    /// UUIDs keep the fixture deterministic across preview reloads.
    static var previewMultiProject: DashboardViewModel {
        let production = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001") ?? UUID()
        let staging = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002") ?? UUID()
        let sandbox = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000003") ?? UUID()

        let stopping = ServerListItem(
            projectID: staging, serverID: 30, name: "worker-03",
            status: .stopping, typeName: "cx22", city: "Ashburn", countryCode: "US"
        )

        return DashboardViewModel(
            projectSections: [
                ProjectSection(
                    projectID: production,
                    projectName: "Production",
                    servers: [
                        ServerListItem(
                            projectID: production, serverID: 10, name: "web-01",
                            status: .running, typeName: "cx32", city: "Falkenstein", countryCode: "DE"
                        ),
                        ServerListItem(
                            projectID: production, serverID: 11, name: "db-01",
                            status: .running, typeName: "cx42", city: "Falkenstein", countryCode: "DE"
                        ),
                    ],
                    isStale: false,
                    errorMessage: nil
                ),
                ProjectSection(
                    projectID: staging,
                    projectName: "Staging",
                    servers: [
                        stopping,
                        ServerListItem(
                            projectID: staging, serverID: 31, name: "cache-01",
                            status: .running, typeName: "cx22", city: "Ashburn", countryCode: "US"
                        ),
                    ],
                    isStale: false,
                    errorMessage: nil
                ),
                ProjectSection(projectID: sandbox, projectName: "Sandbox", servers: [], isStale: false, errorMessage: nil),
            ],
            attention: [stopping],
            monthToDate: 68.42,
            projected: 154.90,
            currency: "EUR",
            lastRefreshed: Date(),
            perProjectBurn: [
                production: (monthToDate: 51.20, projected: 118.40),
                staging: (monthToDate: 17.22, projected: 36.50),
            ]
        )
    }
}
#endif
