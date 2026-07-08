import Foundation
import Testing
@testable import HetznerKit

@Suite("ResponseCache")
struct ResponseCacheTests {
    @Test func storesAndReturnsValueBeforeTTLExpires() async throws {
        let cache = ResponseCache()
        await cache.store("hello", for: "key")

        let value = await cache.value(for: "key", ttl: 1, as: String.self)
        #expect(value == "hello")
    }

    @Test func returnsNilAfterTTLExpires() async throws {
        let cache = ResponseCache()
        await cache.store("hello", for: "key")

        try await Task.sleep(for: .milliseconds(250))

        let value = await cache.value(for: "key", ttl: 0.1, as: String.self)
        #expect(value == nil)
    }

    @Test func returnsNilForMissingKey() async throws {
        let cache = ResponseCache()
        let value = await cache.value(for: "missing", ttl: 10, as: String.self)
        #expect(value == nil)
    }

    @Test func returnsNilOnTypeMismatch() async throws {
        let cache = ResponseCache()
        await cache.store(42, for: "key")
        let value = await cache.value(for: "key", ttl: 10, as: String.self)
        #expect(value == nil)
    }
}
