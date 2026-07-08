import Foundation

/// A minimal in-memory cache with per-read TTL expiry. Generic over any
/// `Sendable` value; each key can hold at most one value at a time.
public actor ResponseCache {
    private struct Entry {
        let value: Any
        let storedAt: ContinuousClock.Instant
    }

    private var storage: [String: Entry] = [:]
    private let clock = ContinuousClock()

    public init() {}

    /// Returns the cached value for `key` as `type` if present and not yet
    /// past `ttl` seconds old. Expired entries are evicted on read.
    public func value<T: Sendable>(for key: String, ttl: TimeInterval, as type: T.Type) -> T? {
        guard let entry = storage[key] else { return nil }

        if elapsedSeconds(since: entry.storedAt) > ttl {
            storage[key] = nil
            return nil
        }

        return entry.value as? T
    }

    public func store<T: Sendable>(_ value: T, for key: String) {
        storage[key] = Entry(value: value, storedAt: clock.now)
    }

    private func elapsedSeconds(since instant: ContinuousClock.Instant) -> TimeInterval {
        let elapsed = clock.now - instant
        let components = elapsed.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
