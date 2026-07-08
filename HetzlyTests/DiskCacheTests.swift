import XCTest
@testable import Hetzly

/// Covers `DiskCache<T>`'s round-trip contract in isolation from any
/// resource-list/view-model plumbing: save → load returns the same payload
/// stamped with a fresh `savedAt`, a miss returns `nil`, and `clear` removes
/// a previously-saved entry. Every test uses a UUID-suffixed key (and tears
/// it down via `clear` in a `defer`) so runs never collide with each other
/// or leave stray files behind in the real Caches directory.
final class DiskCacheTests: XCTestCase {
    private struct Payload: Codable, Sendable, Equatable {
        let value: String
    }

    func test_load_withNothingCached_returnsNil() {
        let cache = DiskCache<Payload>(namespace: "disk-cache-tests")
        let key = "missing-\(UUID())"
        XCTAssertNil(cache.load(key: key))
    }

    func test_saveThenLoad_roundTripsPayloadAndStampsSavedAt() {
        let cache = DiskCache<Payload>(namespace: "disk-cache-tests")
        let key = "round-trip-\(UUID())"
        defer { cache.clear(key: key) }

        let payload = Payload(value: "hello disk cache")
        let before = Date()
        cache.save(payload, key: key)
        let after = Date()

        guard let loaded = cache.load(key: key) else {
            XCTFail("expected a cached value after save")
            return
        }
        XCTAssertEqual(loaded.value, payload)
        XCTAssertGreaterThanOrEqual(loaded.savedAt, before.addingTimeInterval(-1))
        XCTAssertLessThanOrEqual(loaded.savedAt, after.addingTimeInterval(1))
    }

    /// A second `save` under the same key upserts rather than accumulating —
    /// exactly what `ResourceListModel.refresh()` relies on to keep a
    /// project's cached list current across repeated pull-to-refreshes.
    func test_save_overwritesPreviousValueForSameKey() {
        let cache = DiskCache<Payload>(namespace: "disk-cache-tests")
        let key = "overwrite-\(UUID())"
        defer { cache.clear(key: key) }

        cache.save(Payload(value: "first"), key: key)
        cache.save(Payload(value: "second"), key: key)

        XCTAssertEqual(cache.load(key: key)?.value, Payload(value: "second"))
    }

    func test_clear_removesCachedValue() {
        let cache = DiskCache<Payload>(namespace: "disk-cache-tests")
        let key = "clear-\(UUID())"

        cache.save(Payload(value: "to be cleared"), key: key)
        XCTAssertNotNil(cache.load(key: key))

        cache.clear(key: key)
        XCTAssertNil(cache.load(key: key))
    }

    /// Two different `namespace`s never collide on the same key string —
    /// each Resources/Dedicated/Storage Boxes call site gets its own
    /// directory, per the type's doc comment.
    func test_differentNamespaces_withSameKey_doNotCollide() {
        let key = "shared-key-\(UUID())"
        let cacheA = DiskCache<Payload>(namespace: "disk-cache-tests-a-\(UUID())")
        let cacheB = DiskCache<Payload>(namespace: "disk-cache-tests-b-\(UUID())")
        defer {
            cacheA.clear(key: key)
            cacheB.clear(key: key)
        }

        cacheA.save(Payload(value: "from A"), key: key)

        XCTAssertEqual(cacheA.load(key: key)?.value, Payload(value: "from A"))
        XCTAssertNil(cacheB.load(key: key))
    }
}
