import Foundation
import HetznerKit
import Observation

/// Drives `FailoverDetailView`: loads the failover IP plus the account's
/// Robot servers (for the reroute picker), and fires `switchFailover` /
/// `deleteFailoverRouting`.
///
/// Every Robot call here is either the initial load or a direct response to
/// a user action — never a timer or background poll, mirroring
/// `VSwitchDetailViewModel`.
@MainActor
@Observable
final class FailoverDetailViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    let route: FailoverRoute

    private(set) var failover: RobotFailover?
    private(set) var loadState: LoadState = .idle

    /// Every dedicated server on this Robot account, for the reroute picker.
    private(set) var accountServers: [RobotServer] = []
    private(set) var accountServersState: LoadState = .idle

    private(set) var isSwitching = false
    private(set) var switchError: String?
    private(set) var lastActionSuccessText: String?
    private(set) var lastActionSucceeded = false

    private let container: AppContainer

    init(route: FailoverRoute, container: AppContainer) {
        self.route = route
        self.container = container
    }

    private var client: RobotClient? {
        container.robotClient(for: route.accountID)
    }

    // MARK: - Loading

    func load() async {
        guard let client else {
            loadState = .failed("No stored credentials for this account.")
            return
        }
        if failover == nil { loadState = .loading }
        do {
            failover = try await client.failoverIP(ip: route.ip)
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

    func clearSwitchError() {
        switchError = nil
    }

    // MARK: - Reroute

    /// Reroutes traffic for this failover IP to `targetServerIP`. Always
    /// called only after the caller's biometric gate approves — routing
    /// changes are outage-grade, so `FailoverDetailView` gates this
    /// unconditionally, unlike every other destructive action in Dedicated
    /// (which only gates when the user's destructive-actions setting is on).
    func switchRouting(to targetServerIP: String) {
        guard let client, !isSwitching else { return }
        isSwitching = true
        switchError = nil
        lastActionSucceeded = false
        let ip = route.ip
        Task { [weak self] in
            do {
                let updated = try await client.switchFailover(ip: ip, to: targetServerIP)
                self?.failover = updated
                self?.lastActionSuccessText = "Traffic for \(ip) is now routed to \(targetServerIP)."
                self?.lastActionSucceeded = true
            } catch {
                self?.switchError = Self.message(for: error)
            }
            self?.isSwitching = false
        }
    }

    /// Disables routing via `DELETE /failover/{ip}` — the returned object
    /// has `activeServerIP == nil`.
    func removeRouting() {
        guard let client, !isSwitching else { return }
        isSwitching = true
        switchError = nil
        lastActionSucceeded = false
        let ip = route.ip
        Task { [weak self] in
            do {
                let updated = try await client.deleteFailoverRouting(ip: ip)
                self?.failover = updated
                self?.lastActionSuccessText = "Routing for \(ip) removed."
                self?.lastActionSucceeded = true
            } catch {
                self?.switchError = Self.message(for: error)
            }
            self?.isSwitching = false
        }
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? HetznerAPIError {
            return apiError.userMessage
        }
        return "Something went wrong. Please try again."
    }
}
