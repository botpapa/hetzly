import Foundation
import HetznerKit
import Observation

/// Drives `FirewallDetailView`: holds the firewall, resolves server names
/// for the applied-to chips, and performs rule/apply mutations. Every rule
/// mutation replaces the full rule array via `setFirewallRules` (Hetzner's
/// API is set-based, not per-rule), so the whole rules surface shows a
/// single saving state while any change is in flight.
@MainActor
@Observable
final class FirewallDetailViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var firewall: Firewall?
    private(set) var servers: [Server] = []
    private(set) var loadState: LoadState = .idle
    private(set) var isSavingRules = false
    private(set) var isSavingAppliedTo = false
    private(set) var actionError: String?

    let projectID: UUID
    let firewallID: Int
    private let container: AppContainer

    init(projectID: UUID, firewallID: Int, container: AppContainer, initial: Firewall? = nil) {
        self.projectID = projectID
        self.firewallID = firewallID
        self.container = container
        self.firewall = initial
    }

    private var client: CloudClient? { container.cloudClient(for: projectID) }

    var inboundRules: [FirewallRule] { firewall?.rules.filter { $0.direction == .inbound } ?? [] }
    var outboundRules: [FirewallRule] { firewall?.rules.filter { $0.direction == .outbound } ?? [] }

    var appliedServerIDs: Set<Int> {
        Set(firewall?.appliedTo.compactMap { $0.type == .server ? $0.server?.id : nil } ?? [])
    }

    // MARK: - Loading

    func load() async {
        guard let client else {
            loadState = .failed("No stored credentials for this project.")
            return
        }
        if firewall == nil { loadState = .loading }
        do {
            async let firewallLoad = client.firewall(id: firewallID)
            async let serversLoad = client.listServers()
            firewall = try await firewallLoad
            servers = (try? await serversLoad) ?? []
            loadState = .loaded
        } catch {
            loadState = .failed(Self.message(for: error))
        }
    }

    // MARK: - Rule mutations (full-array replace)

    func addRule(_ rule: FirewallRule) async {
        guard let current = firewall else { return }
        await setRules(current.rules + [rule])
    }

    /// Replaces the rule at `index` within the given direction's subset.
    func updateRule(at index: Int, direction: FirewallDirection, with rule: FirewallRule) async {
        guard let current = firewall else { return }
        var rules = current.rules
        let directionIndices = rules.indices.filter { rules[$0].direction == direction }
        guard directionIndices.indices.contains(index) else { return }
        rules[directionIndices[index]] = rule
        await setRules(rules)
    }

    func deleteRule(at index: Int, direction: FirewallDirection) async {
        guard let current = firewall else { return }
        var rules = current.rules
        let directionIndices = rules.indices.filter { rules[$0].direction == direction }
        guard directionIndices.indices.contains(index) else { return }
        rules.remove(at: directionIndices[index])
        await setRules(rules)
    }

    private func setRules(_ rules: [FirewallRule]) async {
        guard let client else { return }
        actionError = nil
        isSavingRules = true
        defer { isSavingRules = false }

        let result = await FirewallActionRunner.run(client: client) {
            try await client.setFirewallRules(id: firewallID, rules: rules)
        }
        switch result {
        case .success:
            await load()
        case .failure(let error):
            actionError = error.userMessage
        }
    }

    // MARK: - Apply / remove

    func apply(toServerIDs serverIDs: [Int]) async {
        guard let client, !serverIDs.isEmpty else { return }
        actionError = nil
        isSavingAppliedTo = true
        defer { isSavingAppliedTo = false }

        let result = await FirewallActionRunner.run(client: client) {
            try await client.applyFirewall(id: firewallID, toServerIDs: serverIDs)
        }
        switch result {
        case .success:
            await load()
        case .failure(let error):
            actionError = error.userMessage
        }
    }

    func remove(fromServerID serverID: Int) async {
        guard let client else { return }
        actionError = nil
        isSavingAppliedTo = true
        defer { isSavingAppliedTo = false }

        let result = await FirewallActionRunner.run(client: client) {
            try await client.removeFirewall(id: firewallID, fromServerIDs: [serverID])
        }
        switch result {
        case .success:
            await load()
        case .failure(let error):
            actionError = error.userMessage
        }
    }

    private static func message(for error: Error) -> String {
        (error as? HetznerAPIError)?.userMessage ?? "Something went wrong. Please try again."
    }
}
