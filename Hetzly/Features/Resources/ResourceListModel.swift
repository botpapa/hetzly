import Foundation
import HetznerKit
import Observation

/// Generic list-loading state for a single Cloud API resource collection
/// (volumes, networks, SSH keys, ...). Every Resources list screen owns one
/// of these, parameterized with its own `load` closure so this type stays
/// UI- and resource-agnostic.
///
/// ## Stale-while-revalidate
/// When constructed with a `cacheKey`, `loadIfNeeded()` first paints from
/// `DiskCache` (marking `isStale = true`) before kicking off the live
/// `load()` closure — mirroring `DashboardViewModel`'s
/// `SnapshotStore`-backed pattern, just generalized to any `Codable` list.
/// A live fetch that succeeds clears `isStale` and writes the fresh list
/// back to disk; one that fails while stale-cached data is on screen leaves
/// that data exactly where it is and reports through `freshnessBanner`
/// instead of demoting to a full-page error — the cached list stays useful
/// even fully offline.
@MainActor
@Observable
final class ResourceListModel<T: Identifiable & Sendable & Codable> {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        /// Carries a `DisplayableError` (not a bare `String`) so the error
        /// banner can offer "Update token…" on an auth failure without
        /// re-parsing the rendered message.
        case failed(DisplayableError)
    }

    private(set) var items: [T] = []
    private(set) var state: LoadState = .idle
    private(set) var isRefreshing = false

    /// `true` when `items` came from `DiskCache` (or from a prior live load
    /// that a subsequent live fetch hasn't yet confirmed still holds) and
    /// haven't been reconfirmed fresh by a successful live fetch. Drives
    /// `freshnessBanner`.
    private(set) var isStale = false
    private(set) var lastLoaded: Date?

    private let load: () async throws -> [T]
    private let cacheKey: String?
    private let cache: DiskCache<[T]>?
    private var didStartLoading = false

    /// - Parameter cacheKey: A key scoped to (resource type, project id) —
    ///   e.g. `"volumes#\(projectID)"`. `nil` opts a particular instance out
    ///   of disk caching entirely (used when there's no project selected
    ///   yet, so there's nothing meaningful to cache under).
    init(load: @escaping () async throws -> [T], cacheKey: String? = nil) {
        self.load = load
        self.cacheKey = cacheKey
        self.cache = cacheKey != nil ? DiskCache<[T]>(namespace: "resource-lists") : nil
    }

    /// Drives the shared "stale/offline" chip in `resourceListBody`. Only
    /// surfaces while there's actually stale data on screen — a clean first
    /// load or a fully-fresh list shows none, matching
    /// `DashboardViewModel.freshnessBanner`'s contract.
    var freshnessBanner: ListFreshness {
        guard isStale else { return .none }
        return (state == .loading || isRefreshing) ? .refreshingCache : .offlineCache
    }

    /// First-appearance load: a no-op on a second call (e.g. a re-triggered
    /// `.task`), regardless of how the first call resolved.
    func loadIfNeeded() async {
        guard !didStartLoading else { return }
        didStartLoading = true
        loadFromCache()
        await refresh()
    }

    /// Pull-to-refresh / post-mutation reload.
    func refresh() async {
        if items.isEmpty {
            state = .loading
        } else {
            isRefreshing = true
        }
        do {
            let fresh = try await load()
            items = fresh
            state = .loaded
            isStale = false
            lastLoaded = Date()
            if let cacheKey, let cache {
                cache.save(fresh, key: cacheKey)
            }
        } catch {
            if isStale {
                // Cache-sourced data is already on screen and the live
                // fetch failed: keep showing it rather than demoting to a
                // full-page error. `freshnessBanner` reports `.offlineCache`
                // from here since `isStale` is untouched.
                state = .loaded
            } else {
                state = .failed(DisplayableError(error))
            }
        }
        isRefreshing = false
    }

    private func loadFromCache() {
        guard let cacheKey, let cache, let cached = cache.load(key: cacheKey) else { return }
        items = cached.value
        isStale = true
        lastLoaded = cached.savedAt
        state = .loaded
    }
}
