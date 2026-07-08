import XCTest
@testable import Hetzly

/// Covers `ResourceListModel<T>`'s stale-while-revalidate contract: a
/// pre-populated `DiskCache` entry paints immediately (marked stale) while
/// the live `load` closure is still in flight, and the live result then
/// replaces it and clears the stale flag. Uses a tiny `TestItem` fixture
/// rather than a real `HetznerKit` resource type — the behavior under test
/// is generic over `T`, so a real Cloud API type would only add noise.
@MainActor
final class ResourceListModelCacheTests: XCTestCase {
    private struct TestItem: Identifiable, Codable, Sendable, Equatable {
        let id: Int
        let name: String
    }

    /// A one-shot async gate: `wait()` suspends until `open()` is called,
    /// letting the test hold the live `load` closure open so it can inspect
    /// the "cached, refreshing" state before letting the live fetch resolve.
    private actor Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var isOpen = false

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { continuation = $0 }
        }

        func open() {
            isOpen = true
            continuation?.resume()
            continuation = nil
        }
    }

    func test_loadIfNeeded_emitsCachedItemsThenLiveItems() async {
        let cacheKey = "test-items#\(UUID())"
        let cache = DiskCache<[TestItem]>(namespace: "resource-lists")
        let cachedItems = [TestItem(id: 1, name: "cached")]
        cache.save(cachedItems, key: cacheKey)
        defer { cache.clear(key: cacheKey) }

        let gate = Gate()
        let liveItems = [TestItem(id: 2, name: "live")]

        let model = ResourceListModel<TestItem>(
            load: {
                await gate.wait()
                return liveItems
            },
            cacheKey: cacheKey
        )

        XCTAssertEqual(model.items, [])
        XCTAssertEqual(model.freshnessBanner, .none)

        let loadTask = Task { await model.loadIfNeeded() }

        // `loadIfNeeded()` paints the cache synchronously before awaiting
        // the live `load()` closure, which is parked on `gate.wait()` —
        // yield a few times so that synchronous work definitely lands
        // before asserting the "cached, refreshing" snapshot.
        for _ in 0..<5 {
            await Task.yield()
        }

        XCTAssertEqual(model.items, cachedItems)
        XCTAssertTrue(model.isStale)
        XCTAssertEqual(model.freshnessBanner, .refreshingCache)

        await gate.open()
        await loadTask.value

        XCTAssertEqual(model.items, liveItems)
        XCTAssertFalse(model.isStale)
        XCTAssertEqual(model.freshnessBanner, .none)
        XCTAssertEqual(model.state, .loaded)

        // The live result was written back to disk, so a fresh model reading
        // the same key sees the live items, not the original cached ones.
        let reloaded = cache.load(key: cacheKey)
        XCTAssertEqual(reloaded?.value, liveItems)
    }

    /// When the live fetch fails but cache-sourced data is already on
    /// screen, the model keeps showing that data (`.loaded`, not `.failed`)
    /// and reports `.offlineCache` instead of demoting to a full-page error.
    func test_loadIfNeeded_liveFailureWithCachePresent_keepsCachedItemsAndReportsOffline() async {
        struct FetchError: Error {}

        let cacheKey = "test-items#\(UUID())"
        let cache = DiskCache<[TestItem]>(namespace: "resource-lists")
        let cachedItems = [TestItem(id: 1, name: "cached")]
        cache.save(cachedItems, key: cacheKey)
        defer { cache.clear(key: cacheKey) }

        let model = ResourceListModel<TestItem>(
            load: { throw FetchError() },
            cacheKey: cacheKey
        )

        await model.loadIfNeeded()

        XCTAssertEqual(model.items, cachedItems)
        XCTAssertTrue(model.isStale)
        XCTAssertEqual(model.state, .loaded)
        XCTAssertEqual(model.freshnessBanner, .offlineCache)
    }

    /// With no cache entry at all, a failing live fetch keeps the original
    /// full-page `.failed` behavior — there's nothing cached to fall back
    /// to, so there's nothing for the offline chip to show either.
    func test_loadIfNeeded_liveFailureWithNoCache_reportsFailedState() async {
        struct FetchError: Error {}

        let cacheKey = "test-items#\(UUID())"
        let cache = DiskCache<[TestItem]>(namespace: "resource-lists")
        defer { cache.clear(key: cacheKey) }

        let model = ResourceListModel<TestItem>(
            load: { throw FetchError() },
            cacheKey: cacheKey
        )

        await model.loadIfNeeded()

        XCTAssertEqual(model.items, [])
        XCTAssertFalse(model.isStale)
        XCTAssertEqual(model.freshnessBanner, .none)
        if case .failed = model.state {
            // expected
        } else {
            XCTFail("expected .failed state, got \(model.state)")
        }
    }
}
