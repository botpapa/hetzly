import Foundation
import HetznerKit
import Observation

/// Drives `VSwitchDetailView`: loads the vSwitch plus the account's Robot
/// servers (for the add-server picker), and fires rename/VLAN-change,
/// add-server, remove-server, and delete actions. Every Robot call here is
/// either the initial load or a direct response to a user action — never a
/// timer or background poll, mirroring `DedicatedServerDetailViewModel`.
@MainActor
@Observable
final class VSwitchDetailViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    let route: VSwitchRoute

    private(set) var vSwitch: RobotVSwitch?
    private(set) var loadState: LoadState = .idle

    /// Every dedicated server on this Robot account, for the add-server
    /// picker — filtered client-side to exclude servers already attached.
    private(set) var accountServers: [RobotServer] = []
    private(set) var accountServersState: LoadState = .idle

    private(set) var isPerformingAction = false
    private(set) var actionError: String?
    private(set) var lastActionSuccessText: String?
    private(set) var lastActionSucceeded = false

    /// Set to `true` once `deleteVSwitch` succeeds, so the view can pop back
    /// to the list.
    private(set) var didDelete = false

    private let container: AppContainer

    init(route: VSwitchRoute, container: AppContainer) {
        self.route = route
        self.container = container
    }

    private var client: RobotClient? {
        container.robotClient(for: route.accountID)
    }

    var attachedServerNumbers: Set<Int> {
        Set((vSwitch?.servers ?? []).map(\.serverNumber))
    }

    var availableServersToAdd: [RobotServer] {
        accountServers.filter { !attachedServerNumbers.contains($0.serverNumber) }
    }

    // MARK: - Loading

    func load() async {
        guard let client else {
            loadState = .failed("No stored credentials for this account.")
            return
        }
        if vSwitch == nil { loadState = .loading }
        do {
            vSwitch = try await client.vSwitch(id: route.vSwitchID)
            loadState = .loaded
        } catch {
            loadState = .failed(Self.message(for: error))
        }
    }

    func loadAccountServers() async {
        guard let client else { return }
        accountServersState = .loading
        do {
            accountServers = try await client.listServers()
            accountServersState = .loaded
        } catch {
            accountServersState = .failed(Self.message(for: error))
        }
    }

    func acknowledgeSuccess() {
        lastActionSucceeded = false
    }

    func clearActionError() {
        actionError = nil
    }

    // MARK: - Rename / change VLAN

    @discardableResult
    func update(name: String, vlan: Int) async -> Bool {
        guard let client else { return false }
        isPerformingAction = true
        actionError = nil
        defer { isPerformingAction = false }
        do {
            vSwitch = try await client.updateVSwitch(id: route.vSwitchID, name: name, vlan: vlan)
            lastActionSuccessText = "vSwitch updated."
            lastActionSucceeded = true
            return true
        } catch {
            actionError = Self.message(for: error)
            return false
        }
    }

    // MARK: - Servers

    func addServers(_ serverNumbers: [Int]) {
        guard let client, !isPerformingAction, !serverNumbers.isEmpty else { return }
        isPerformingAction = true
        actionError = nil
        lastActionSucceeded = false
        let vSwitchID = route.vSwitchID
        Task { [weak self] in
            do {
                try await client.addVSwitchServers(id: vSwitchID, serverNumbers: serverNumbers)
                self?.lastActionSuccessText = serverNumbers.count == 1 ? "Server added." : "\(serverNumbers.count) servers added."
                self?.lastActionSucceeded = true
                await self?.load()
            } catch {
                self?.actionError = Self.message(for: error)
            }
            self?.isPerformingAction = false
        }
    }

    func removeServer(_ serverNumber: Int) {
        guard let client, !isPerformingAction else { return }
        isPerformingAction = true
        actionError = nil
        lastActionSucceeded = false
        let vSwitchID = route.vSwitchID
        Task { [weak self] in
            do {
                try await client.removeVSwitchServers(id: vSwitchID, serverNumbers: [serverNumber])
                self?.lastActionSuccessText = "Server removed."
                self?.lastActionSucceeded = true
                await self?.load()
            } catch {
                self?.actionError = Self.message(for: error)
            }
            self?.isPerformingAction = false
        }
    }

    // MARK: - Delete

    func delete() {
        guard let client, !isPerformingAction else { return }
        isPerformingAction = true
        actionError = nil
        let vSwitchID = route.vSwitchID
        Task { [weak self] in
            do {
                try await client.deleteVSwitch(id: vSwitchID)
                self?.didDelete = true
            } catch {
                self?.actionError = Self.message(for: error)
            }
            self?.isPerformingAction = false
        }
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? HetznerAPIError {
            return apiError.userMessage
        }
        return "Something went wrong. Please try again."
    }
}
