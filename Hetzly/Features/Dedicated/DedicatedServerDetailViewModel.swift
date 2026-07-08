import Foundation
import HetznerKit
import Observation

/// Drives `DedicatedServerDetailView`: loads the server plus the catalog
/// data its action sheets need (reset options, boot configuration, rescue
/// status, SSH keys, this server's IPs and their PTR records), and fires
/// reset/wake/rescue/rDNS actions.
///
/// Every Robot call here is either the initial load or a direct response to
/// a user action (pull-to-refresh, opening a sheet, confirming an action) —
/// never a timer or background poll, per the M3 hard constraint. Robot has
/// no `Action`-polling concept like Cloud's `ActionTracker`: reset/wake/
/// rescue calls complete (or fail) in one round trip.
@MainActor
@Observable
final class DedicatedServerDetailViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// The rescue root password, shown exactly once via `SensitiveSecretCard`.
    /// Never logged.
    struct RevealedRescuePassword: Identifiable, Equatable {
        let id = UUID()
        let password: String
    }

    let route: RobotServerRoute

    private(set) var server: RobotServer?
    private(set) var loadState: LoadState = .idle

    private(set) var resetInfo: RobotResetInfo?
    private(set) var resetInfoState: LoadState = .idle

    private(set) var bootConfiguration: RobotBootConfiguration?
    private(set) var bootConfigState: LoadState = .idle

    private(set) var rescue: RobotRescue?
    private(set) var rescueState: LoadState = .idle

    private(set) var sshKeys: [RobotSSHKey] = []
    private(set) var sshKeysState: LoadState = .idle

    /// This server's own IPs, filtered client-side from the account-wide
    /// `listIPs()` (Robot has no per-server IP endpoint) — per CONTRACTS.md:
    /// "list this server's IPs from server detail/listIPs filtered by
    /// server_number".
    private(set) var ips: [RobotIP] = []
    private(set) var ipsState: LoadState = .idle

    /// PTR record per IP string, loaded one `rdns(ip:)` call at a time after
    /// `ips` loads (Robot has no bulk rDNS lookup).
    private(set) var rdnsByIP: [String: String] = [:]
    private(set) var rdnsState: LoadState = .idle

    private(set) var isPerformingAction = false
    private(set) var actionError: String?
    private(set) var lastActionSuccessText: String?
    /// Flips to `true` right after an action finishes successfully, so the
    /// view can fire a one-shot success toast/haptic. The view resets it.
    private(set) var lastActionSucceeded = false

    private(set) var revealedRescuePassword: RevealedRescuePassword?

    private(set) var isRenaming = false
    private(set) var renameError: String?

    private let container: AppContainer

    init(route: RobotServerRoute, container: AppContainer) {
        self.route = route
        self.container = container
    }

    private var client: RobotClient? {
        container.robotClient(for: route.accountID)
    }

    // MARK: - Loading

    func load(forceRefresh: Bool = false) async {
        guard let client else {
            loadState = .failed("No stored credentials for this account.")
            return
        }
        if server == nil { loadState = .loading }
        do {
            let loaded = try await client.server(number: route.serverNumber)
            server = loaded
            loadState = .loaded
        } catch {
            loadState = .failed(Self.message(for: error))
        }
    }

    func loadResetOptions() async {
        guard let client else { return }
        resetInfoState = .loading
        do {
            resetInfo = try await client.resetOptions(serverNumber: route.serverNumber)
            resetInfoState = .loaded
        } catch {
            resetInfoState = .failed(Self.message(for: error))
        }
    }

    func loadBootConfiguration() async {
        guard let client else { return }
        bootConfigState = .loading
        do {
            bootConfiguration = try await client.bootConfiguration(serverNumber: route.serverNumber)
            bootConfigState = .loaded
        } catch {
            bootConfigState = .failed(Self.message(for: error))
        }
    }

    func loadRescue() async {
        guard let client else { return }
        rescueState = .loading
        do {
            rescue = try await client.rescue(serverNumber: route.serverNumber)
            rescueState = .loaded
        } catch {
            rescueState = .failed(Self.message(for: error))
        }
    }

    func loadSSHKeys() async {
        guard let client else { return }
        sshKeysState = .loading
        do {
            sshKeys = try await client.listSSHKeys()
            sshKeysState = .loaded
        } catch {
            sshKeysState = .failed(Self.message(for: error))
        }
    }

    func loadIPs() async {
        guard let client else { return }
        ipsState = .loading
        do {
            let all = try await client.listIPs()
            ips = all.filter { $0.serverNumber == route.serverNumber }
            ipsState = .loaded
        } catch {
            ipsState = .failed(Self.message(for: error))
        }
    }

    /// Loads the PTR record for each of this server's IPs. Must run after
    /// `loadIPs()` — sequential, one Robot request per IP, since every
    /// request already funnels through `RobotClient`'s single-in-flight
    /// queue and there's no bulk rDNS endpoint to prefer instead.
    func loadRDNS() async {
        guard let client else { return }
        guard !ips.isEmpty else {
            rdnsByIP = [:]
            rdnsState = .loaded
            return
        }
        rdnsState = .loading
        var result: [String: String] = [:]
        for ip in ips {
            if let record = try? await client.rdns(ip: ip.ip) {
                result[ip.ip] = record.ptr
            }
        }
        rdnsByIP = result
        rdnsState = .loaded
    }

    func acknowledgeSuccess() {
        lastActionSucceeded = false
    }

    func clearActionError() {
        actionError = nil
    }

    func dismissRevealedRescuePassword() {
        revealedRescuePassword = nil
    }

    // MARK: - Rename

    @discardableResult
    func rename(to newName: String) async -> Bool {
        guard let client else { return false }
        isRenaming = true
        renameError = nil
        defer { isRenaming = false }
        do {
            server = try await client.rename(serverNumber: route.serverNumber, to: newName)
            return true
        } catch {
            renameError = Self.message(for: error)
            return false
        }
    }

    // MARK: - Reset

    func reset(type: RobotResetType) {
        guard let client, !isPerformingAction else { return }
        isPerformingAction = true
        actionError = nil
        lastActionSucceeded = false
        let serverNumber = route.serverNumber
        Task { [weak self] in
            do {
                try await client.reset(serverNumber: serverNumber, type: type)
                self?.lastActionSuccessText = "\(type.title) sent."
                self?.lastActionSucceeded = true
            } catch {
                self?.actionError = Self.message(for: error)
            }
            self?.isPerformingAction = false
        }
    }

    // MARK: - Wake on LAN

    func wake() {
        guard let client, !isPerformingAction else { return }
        isPerformingAction = true
        actionError = nil
        lastActionSucceeded = false
        let serverNumber = route.serverNumber
        Task { [weak self] in
            do {
                try await client.wake(serverNumber: serverNumber)
                self?.lastActionSuccessText = "Wake-on-LAN sent."
                self?.lastActionSucceeded = true
            } catch {
                self?.actionError = Self.message(for: error)
            }
            self?.isPerformingAction = false
        }
    }

    // MARK: - Rescue mode

    func enableRescue(os: String, sshKeyFingerprints: [String]) {
        guard let client, !isPerformingAction else { return }
        isPerformingAction = true
        actionError = nil
        lastActionSucceeded = false
        let serverNumber = route.serverNumber
        Task { [weak self] in
            do {
                let result = try await client.enableRescue(
                    serverNumber: serverNumber, os: os, sshKeyFingerprints: sshKeyFingerprints
                )
                self?.rescue = result
                if let password = result.password, !password.isEmpty {
                    self?.revealedRescuePassword = RevealedRescuePassword(password: password)
                }
                self?.lastActionSuccessText = "Rescue mode armed."
                self?.lastActionSucceeded = true
                await self?.load(forceRefresh: true)
            } catch {
                self?.actionError = Self.message(for: error)
            }
            self?.isPerformingAction = false
        }
    }

    func disableRescue() {
        guard let client, !isPerformingAction else { return }
        isPerformingAction = true
        actionError = nil
        lastActionSucceeded = false
        let serverNumber = route.serverNumber
        Task { [weak self] in
            do {
                let result = try await client.disableRescue(serverNumber: serverNumber)
                self?.rescue = result
                self?.lastActionSuccessText = "Rescue mode disabled."
                self?.lastActionSucceeded = true
            } catch {
                self?.actionError = Self.message(for: error)
            }
            self?.isPerformingAction = false
        }
    }

    // MARK: - Reverse DNS

    @discardableResult
    func setRDNS(ip: String, ptr: String) async -> Bool {
        guard let client else { return false }
        isPerformingAction = true
        actionError = nil
        defer { isPerformingAction = false }
        do {
            let updated = try await client.setRDNS(ip: ip, ptr: ptr)
            rdnsByIP[ip] = updated.ptr
            lastActionSuccessText = "Reverse DNS updated."
            lastActionSucceeded = true
            return true
        } catch {
            actionError = Self.message(for: error)
            return false
        }
    }

    @discardableResult
    func deleteRDNS(ip: String) async -> Bool {
        guard let client else { return false }
        isPerformingAction = true
        actionError = nil
        defer { isPerformingAction = false }
        do {
            try await client.deleteRDNS(ip: ip)
            rdnsByIP.removeValue(forKey: ip)
            lastActionSuccessText = "Reverse DNS reset to default."
            lastActionSucceeded = true
            return true
        } catch {
            actionError = Self.message(for: error)
            return false
        }
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? HetznerAPIError {
            return apiError.userMessage
        }
        return "Something went wrong. Please try again."
    }
}
