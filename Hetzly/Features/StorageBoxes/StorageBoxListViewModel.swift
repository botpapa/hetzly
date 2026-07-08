import Foundation
import HetznerKit
import Observation

/// Drives `StorageBoxesView`'s list: loads Storage Boxes for the selected
/// account. Mirrors `DedicatedListViewModel`'s shape, including its
/// `DiskCache`-backed stale-while-revalidate behavior: `load(...)` first
/// paints whatever's cached for `accountID` (marking `isStale`) before the
/// live `StorageBoxClient.listStorageBoxes()` call resolves, and a live
/// fetch that fails while cached data is on screen keeps that data visible
/// (via `freshnessBanner`) instead of replacing it with a full-page error.
@MainActor
@Observable
final class StorageBoxListViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var boxes: [StorageBox] = []
    private(set) var loadState: LoadState = .idle
    private(set) var isStale = false
    private(set) var isRefreshing = false

    private let cache = DiskCache<[StorageBox]>(namespace: "storage-boxes")
    private var loadedAccountID: UUID?

    var freshnessBanner: ListFreshness {
        guard isStale else { return .none }
        return (loadState == .loading || isRefreshing) ? .refreshingCache : .offlineCache
    }

    func load(accountID: UUID?, container: AppContainer) async {
        guard let accountID else {
            boxes = []
            loadState = .idle
            isStale = false
            loadedAccountID = nil
            return
        }

        if loadedAccountID != accountID {
            loadedAccountID = accountID
            boxes = []
            isStale = false
            if let cached = cache.load(key: cacheKey(accountID)) {
                boxes = cached.value
                isStale = true
            }
        }

        guard let client = container.storageBoxClient(for: accountID) else {
            boxes = []
            loadState = .failed("No stored token for this account.")
            isStale = false
            return
        }

        if boxes.isEmpty {
            loadState = .loading
        } else {
            isRefreshing = true
        }
        do {
            let loaded = try await client.listStorageBoxes()
            let sorted = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            boxes = sorted
            loadState = .loaded
            isStale = false
            cache.save(sorted, key: cacheKey(accountID))
        } catch {
            if isStale {
                loadState = .loaded
            } else {
                loadState = .failed(Self.message(for: error))
            }
        }
        isRefreshing = false
    }

    private func cacheKey(_ accountID: UUID) -> String {
        "storage-boxes#\(accountID)"
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? HetznerAPIError {
            return apiError.userMessage
        }
        return "Something went wrong. Please try again."
    }
}
