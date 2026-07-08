import Foundation
import HetznerKit
import Observation

/// Drives `DedicatedView`'s server list: loads Robot servers for the
/// selected account. No auto-refresh, no background polling — only
/// `load(...)` calls the view fires explicitly (initial load, account
/// switch, pull-to-refresh), per the M3 hard constraint on Robot API usage.
@MainActor
@Observable
final class DedicatedListViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var servers: [RobotServer] = []
    private(set) var loadState: LoadState = .idle

    /// Loads (or reloads) the server list for `accountID`. `forceRefresh`
    /// bypasses `RobotClient`'s 5-minute response cache — used for explicit
    /// pull-to-refresh so the user can always get a fresh read on demand,
    /// while every other load path (initial appearance, account switch)
    /// happily reuses the cache to stay within the conservative request
    /// budget.
    func load(accountID: UUID?, container: AppContainer, forceRefresh: Bool = false) async {
        guard let accountID else {
            servers = []
            loadState = .idle
            return
        }
        guard let client = container.robotClient(for: accountID) else {
            servers = []
            loadState = .failed("No stored credentials for this account.")
            return
        }
        if servers.isEmpty { loadState = .loading }
        do {
            let loaded = try await client.listServers(forceRefresh: forceRefresh)
            servers = loaded.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            loadState = .loaded
        } catch {
            loadState = .failed(Self.message(for: error))
        }
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? HetznerAPIError {
            return apiError.userMessage
        }
        return "Something went wrong. Please try again."
    }
}
