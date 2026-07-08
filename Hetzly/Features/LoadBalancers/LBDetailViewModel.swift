import Foundation
import HetznerKit
import Observation

/// Drives `LBDetailView`: loads the load balancer (plus servers for target
/// name resolution and networks/types for the danger zone), loads metrics
/// for the selected chart range, and runs every mutating action through
/// `ActionTracker` with a single busy flag + error surface.
@MainActor
@Observable
final class LBDetailViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var loadBalancer: LoadBalancer?
    private(set) var servers: [Server] = []
    private(set) var networks: [Network] = []
    private(set) var types: [LoadBalancerType] = []
    private(set) var loadState: LoadState = .idle

    private(set) var metrics: ServerMetrics?
    private(set) var metricsState: LoadState = .idle
    var selectedRange: MetricsRange = .oneHour {
        didSet {
            guard oldValue != selectedRange else { return }
            let range = selectedRange
            Task { [weak self] in await self?.loadMetrics(range: range) }
        }
    }

    /// A human label for the in-flight mutation ("Adding service…"), or nil
    /// when idle.
    private(set) var busyLabel: String?
    private(set) var actionError: String?
    /// Set once a `delete` completes, telling the view to pop back.
    private(set) var didDelete = false

    let projectID: UUID
    let loadBalancerID: Int
    private let container: AppContainer

    init(projectID: UUID, loadBalancerID: Int, container: AppContainer, initial: LoadBalancer? = nil) {
        self.projectID = projectID
        self.loadBalancerID = loadBalancerID
        self.container = container
        self.loadBalancer = initial
    }

    private var client: CloudClient? { container.cloudClient(for: projectID) }

    // MARK: - Loading

    func load() async {
        guard let client else {
            loadState = .failed("No stored credentials for this project.")
            return
        }
        if loadBalancer == nil { loadState = .loading }
        do {
            async let lbLoad = client.loadBalancer(id: loadBalancerID)
            async let serversLoad = client.listServers()
            loadBalancer = try await lbLoad
            servers = (try? await serversLoad) ?? []
            loadState = .loaded
        } catch {
            loadState = .failed(Self.message(for: error))
        }
    }

    /// Danger-zone reference data, loaded lazily the first time the
    /// disclosure opens.
    func loadDangerZoneData() async {
        guard let client else { return }
        if types.isEmpty {
            types = (try? await client.listLoadBalancerTypes()) ?? []
        }
        if networks.isEmpty {
            networks = (try? await client.listNetworks()) ?? []
        }
    }

    func loadMetrics(range: MetricsRange? = nil) async {
        guard let client else { return }
        let range = range ?? selectedRange
        metricsState = .loading
        let end = Date()
        let start = end.addingTimeInterval(-range.duration)
        do {
            metrics = try await client.loadBalancerMetrics(
                id: loadBalancerID,
                types: Set(LBMetricsType.allCases),
                start: start,
                end: end,
                step: range.step
            )
            metricsState = .loaded
        } catch {
            metrics = nil
            metricsState = .failed(Self.message(for: error))
        }
    }

    // MARK: - Mutations

    func changeAlgorithm(to type: LBAlgorithmType) async {
        await run(label: "Changing algorithm…") { client in
            try await client.changeLBAlgorithm(id: self.loadBalancerID, type: type)
        }
    }

    func addService(_ service: LBService) async {
        await run(label: "Adding service…") { client in
            try await client.addLBService(id: self.loadBalancerID, service: service)
        }
    }

    func updateService(_ service: LBService) async {
        await run(label: "Updating service…") { client in
            try await client.updateLBService(id: self.loadBalancerID, service: service)
        }
    }

    func deleteService(listenPort: Int) async {
        await run(label: "Removing service…") { client in
            try await client.deleteLBService(id: self.loadBalancerID, listenPort: listenPort)
        }
    }

    func addTarget(_ target: LBTarget) async {
        await run(label: "Adding target…") { client in
            try await client.addLBTarget(id: self.loadBalancerID, target: target)
        }
    }

    func removeTarget(_ target: LBTarget) async {
        await run(label: "Removing target…") { client in
            try await client.removeLBTarget(id: self.loadBalancerID, target: target)
        }
    }

    func changeType(toTypeName typeName: String) async {
        await run(label: "Changing type…") { client in
            try await client.changeLBType(id: self.loadBalancerID, typeName: typeName)
        }
    }

    func attachToNetwork(networkID: Int) async {
        await run(label: "Attaching to network…") { client in
            try await client.attachLBToNetwork(id: self.loadBalancerID, networkID: networkID)
        }
    }

    func detachFromNetwork(networkID: Int) async {
        await run(label: "Detaching from network…") { client in
            try await client.detachLBFromNetwork(id: self.loadBalancerID, networkID: networkID)
        }
    }

    func setDeleteProtection(_ enabled: Bool) async {
        await run(label: enabled ? "Enabling protection…" : "Disabling protection…") { client in
            try await client.changeLBProtection(id: self.loadBalancerID, delete: enabled)
        }
    }

    func delete() async {
        guard let client else { return }
        actionError = nil
        busyLabel = "Deleting…"
        defer { busyLabel = nil }
        do {
            try await client.deleteLoadBalancer(id: loadBalancerID)
            didDelete = true
        } catch {
            actionError = Self.message(for: error)
        }
    }

    /// Fires an action-returning mutation, tracks it to completion, then
    /// reloads. All mutations share `busyLabel`/`actionError`.
    private func run(label: String, _ operation: (CloudClient) async throws -> Action) async {
        guard let client, busyLabel == nil else { return }
        actionError = nil
        busyLabel = label
        defer { busyLabel = nil }

        do {
            let action = try await operation(client)
            let tracker = ActionTracker(client: client)
            for await update in await tracker.track(actionID: action.id) {
                switch update {
                case .finished:
                    await load()
                case .failed(let error):
                    actionError = error.userMessage
                case .timedOut:
                    actionError = "This is taking longer than expected. Check back shortly."
                case .progress:
                    continue
                }
            }
        } catch {
            actionError = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        (error as? HetznerAPIError)?.userMessage ?? "Something went wrong. Please try again."
    }
}
