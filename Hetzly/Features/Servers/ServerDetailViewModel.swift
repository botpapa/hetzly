import Foundation
import HetznerKit
import Observation

/// Drives `ServerDetailView`: loads the server, fires power actions and
/// tracks their progress via `ActionTracker`, and loads metrics for the
/// selected chart range.
@MainActor
@Observable
final class ServerDetailViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// A power/lifecycle action currently in flight, with the latest
    /// progress percentage reported by `ActionTracker`.
    struct ActiveAction: Equatable {
        let kind: PowerAction
        var progress: Int
    }

    let route: ServerRoute

    private(set) var server: Server?
    private(set) var loadState: LoadState = .idle

    private(set) var activeAction: ActiveAction?
    private(set) var actionError: String?
    /// Flips to `true` right after an action finishes successfully, so the
    /// view can fire a one-shot success haptic / mascot celebration. The
    /// view is responsible for resetting it back to `false`.
    private(set) var lastActionSucceeded = false
    /// Which action last succeeded — read by the view to pick the success
    /// toast's copy and mascot state. Stays set after `lastActionSucceeded`
    /// resets so the toast can finish its exit animation.
    private(set) var lastSucceededAction: PowerAction?
    /// Set once a `delete` action completes, telling the view to pop back.
    private(set) var didDeleteServer = false

    private(set) var metrics: ServerMetrics?
    private(set) var metricsState: LoadState = .idle
    var selectedRange: MetricsRange = .oneHour {
        didSet {
            guard oldValue != selectedRange else { return }
            let range = selectedRange
            Task { [weak self] in await self?.loadMetrics(range: range) }
        }
    }

    private let container: AppContainer
    // nonisolated(unsafe): written only from @MainActor methods; deinit (nonisolated)
    // may only cancel, which Task supports from any context.
    @ObservationIgnored
    private nonisolated(unsafe) var actionTask: Task<Void, Never>?

    init(route: ServerRoute, container: AppContainer) {
        self.route = route
        self.container = container
    }

    deinit {
        actionTask?.cancel()
    }

    private var client: CloudClient? {
        container.cloudClient(for: route.projectID)
    }

    // MARK: - Loading

    func load() async {
        guard let client else {
            loadState = .failed("No stored credentials for this project.")
            return
        }
        if server == nil { loadState = .loading }
        do {
            let loaded = try await client.server(id: route.serverID)
            server = loaded
            loadState = .loaded
        } catch {
            loadState = .failed(Self.message(for: error))
        }
    }

    func loadMetrics(range: MetricsRange? = nil) async {
        guard let client else { return }
        let range = range ?? selectedRange
        metricsState = .loading
        let end = Date()
        let start = end.addingTimeInterval(-range.duration)
        do {
            let result = try await client.serverMetrics(
                serverID: route.serverID,
                types: [.cpu, .disk, .network],
                start: start,
                end: end,
                step: range.step
            )
            metrics = result
            metricsState = .loaded
        } catch {
            metrics = nil
            metricsState = .failed(Self.message(for: error))
        }
    }

    // MARK: - Actions

    func clearActionError() {
        actionError = nil
    }

    func acknowledgeSuccess() {
        lastActionSucceeded = false
    }

    func runAction(_ kind: PowerAction) {
        guard let client, activeAction == nil else { return }
        actionError = nil
        lastActionSucceeded = false
        actionTask?.cancel()
        actionTask = Task { [weak self] in
            await self?.track(kind, using: client)
        }
    }

    private func track(_ kind: PowerAction, using client: CloudClient) async {
        activeAction = ActiveAction(kind: kind, progress: 0)
        do {
            let action = try await perform(kind, on: client)
            activeAction = ActiveAction(kind: kind, progress: action.progress)
            let tracker = ActionTracker(client: client)
            for await update in await tracker.track(actionID: action.id) {
                switch update {
                case .progress(let running):
                    activeAction = ActiveAction(kind: kind, progress: running.progress)
                case .finished:
                    activeAction = nil
                    lastActionSucceeded = true
                    lastSucceededAction = kind
                    if kind == .delete {
                        didDeleteServer = true
                    } else {
                        await load()
                    }
                case .failed(let underlying):
                    // Contract types `.failed`'s payload as "HetznerAPIError
                    // or action error" — treated generically as `Error` here
                    // so this keeps working regardless of which concrete
                    // type ActionTracker settles on.
                    activeAction = nil
                    actionError = Self.message(for: underlying)
                case .timedOut:
                    activeAction = nil
                    actionError = "This is taking longer than expected. Check back shortly."
                }
            }
        } catch {
            activeAction = nil
            actionError = Self.message(for: error)
        }
    }

    private func perform(_ kind: PowerAction, on client: CloudClient) async throws -> Action {
        switch kind {
        case .powerOn: try await client.powerOn(serverID: route.serverID)
        case .shutdown: try await client.shutdown(serverID: route.serverID)
        case .reboot: try await client.reboot(serverID: route.serverID)
        case .reset: try await client.reset(serverID: route.serverID)
        case .powerOff: try await client.powerOff(serverID: route.serverID)
        case .delete: try await client.deleteServer(id: route.serverID)
        }
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? HetznerAPIError {
            return apiError.userMessage
        }
        return "Something went wrong. Please try again."
    }
}
