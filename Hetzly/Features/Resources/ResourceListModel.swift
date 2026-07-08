import Foundation
import HetznerKit
import Observation

/// Generic list-loading state for a single Cloud API resource collection
/// (volumes, networks, SSH keys, ...). Every Resources list screen owns one
/// of these, parameterized with its own `load` closure so this type stays
/// UI- and resource-agnostic.
@MainActor
@Observable
final class ResourceListModel<T: Identifiable & Sendable> {
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

    private let load: () async throws -> [T]

    init(load: @escaping () async throws -> [T]) {
        self.load = load
    }

    /// First-appearance load: a no-op if already loaded or in flight.
    func loadIfNeeded() async {
        guard items.isEmpty, state == .idle else { return }
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
            items = try await load()
            state = .loaded
        } catch {
            state = .failed(DisplayableError(error))
        }
        isRefreshing = false
    }
}
