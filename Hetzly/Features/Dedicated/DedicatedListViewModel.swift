import Foundation
import HetznerKit
import Observation

/// Drives `DedicatedView`'s server list: loads Robot servers for the
/// selected account. No auto-refresh, no background polling — only
/// `load(...)` calls the view fires explicitly (initial load, account
/// switch, pull-to-refresh), per the M3 hard constraint on Robot API usage.
///
/// ## Stale-while-revalidate
/// `load(...)` first paints from `DiskCache` (keyed by account) — marking
/// `isStale = true` — before issuing the live `RobotClient.listServers()`
/// call, mirroring `ResourceListModel`'s pattern. This is purely a
/// cold-launch/offline rendering concern layered on top of the existing
/// request budget: it adds no extra Robot API calls of its own (a cache read
/// is a local file read), and `forceRefresh` still only ever bypasses
/// `RobotClient`'s own 5-minute response cache on an explicit pull-to-refresh
/// exactly as before.
@MainActor
@Observable
final class DedicatedListViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        /// Carries a `DisplayableError` so the failed state can tell an
        /// auth failure (bad Robot webservice credentials) apart from any
        /// other error and point at Settings → Robot Accounts — there's no
        /// `UpdateTokenSheet` equivalent for Robot, so that's the honest fix.
        case failed(DisplayableError)
    }

    private(set) var servers: [RobotServer] = []
    private(set) var loadState: LoadState = .idle
    private(set) var isStale = false
    private(set) var isRefreshing = false

    private let cache = DiskCache<[RobotServer]>(namespace: "dedicated-servers")
    /// The account the currently-cached `servers` belong to — guards against
    /// painting stale cached data from a *different* account into a fresh
    /// `load(accountID:)` call while the live fetch for the new account is
    /// still in flight.
    private var loadedAccountID: UUID?

    var freshnessBanner: ListFreshness {
        guard isStale else { return .none }
        return (loadState == .loading || isRefreshing) ? .refreshingCache : .offlineCache
    }

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
            isStale = false
            loadedAccountID = nil
            return
        }

        if loadedAccountID != accountID {
            // Switched account: reset and paint whatever's cached for the
            // new account before the live fetch resolves.
            loadedAccountID = accountID
            servers = []
            isStale = false
            if let cached = cache.load(key: cacheKey(accountID)) {
                servers = cached.value
                isStale = true
            }
        }

        guard let client = container.robotClient(for: accountID) else {
            servers = []
            loadState = .failed(DisplayableError(message: "No stored credentials for this account."))
            isStale = false
            return
        }

        if servers.isEmpty {
            loadState = .loading
        } else {
            isRefreshing = true
        }
        do {
            let loaded = try await client.listServers(forceRefresh: forceRefresh)
            let sorted = loaded.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            servers = sorted
            loadState = .loaded
            isStale = false
            cache.save(sorted, key: cacheKey(accountID))
        } catch {
            if isStale {
                // Cached data from disk is already on screen — keep it and
                // let `freshnessBanner` report "Offline" instead of
                // replacing it with a full-page error.
                loadState = .loaded
            } else {
                loadState = .failed(DisplayableError(error))
            }
        }
        isRefreshing = false
    }

    private func cacheKey(_ accountID: UUID) -> String {
        "robot-servers#\(accountID)"
    }
}
