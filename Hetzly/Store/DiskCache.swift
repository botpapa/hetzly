import Foundation

/// Generic file-backed JSON cache powering stale-while-revalidate reads on
/// cold launch for every list screen that isn't already backed by
/// `SnapshotStore` (Dashboard's SwiftData-based server cache). One JSON file
/// per key inside the app's Caches directory (`Library/Caches/DiskCache/<namespace>/`)
/// — Caches is the right place for this: every payload cached here is
/// non-secret, per-account/project-scoped *list* data (volumes, networks,
/// Robot servers, Storage Boxes, ...) that the app can always re-fetch from
/// the network, so it's fine for the system to purge it under disk pressure.
/// Nothing about token/credential storage lives here — that stays in
/// Keychain, untouched by this type.
///
/// Mirrors `SnapshotStore`'s stale-while-revalidate shape (payload + saved
/// timestamp, corrupt reads self-heal) but is resource-agnostic and needs no
/// `ModelContext` / SwiftData schema registration, so call sites that don't
/// have an `AppContainer` on hand (every Resources list, Dedicated, Storage
/// Boxes) can construct one directly with no DI plumbing.
struct DiskCache<T: Codable & Sendable>: Sendable {
    private let directory: URL

    /// `namespace` scopes the cache directory (e.g. "resource-lists",
    /// "dedicated-servers", "storage-boxes") so unrelated callers can never
    /// collide on a bare key, even if two features happen to pick the same
    /// key string.
    init(namespace: String, fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.directory = base
            .appendingPathComponent("DiskCache", isDirectory: true)
            .appendingPathComponent(namespace, isDirectory: true)
    }

    private struct Envelope: Codable {
        let savedAt: Date
        let payload: T
    }

    /// Reads the cached value for `key`, or `nil` if there's nothing cached
    /// yet or the cached file is unreadable/corrupt. A corrupt file is
    /// deleted on the way out (self-heal), so a future `load` doesn't keep
    /// failing on the same bad bytes and a future `save` doesn't have to
    /// contend with a stale leftover.
    func load(key: String) -> (value: T, savedAt: Date)? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return (envelope.payload, envelope.savedAt)
    }

    /// Upserts `value` for `key`, stamped with the current time. Best-effort:
    /// failures (disk full, sandbox denial, ...) are silently swallowed —
    /// this is a cache, not a source of truth, and a failed write just means
    /// the next cold launch falls back to the loading spinner instead of
    /// stale-while-revalidate.
    func save(_ value: T, key: String) {
        let envelope = Envelope(savedAt: Date(), payload: value)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    /// Drops the cached value for `key`, if any. Not currently wired into
    /// any call site (every list screen just lets a fresh `save` overwrite
    /// the old value) — kept as a small, obviously-useful primitive for a
    /// future "sign out clears cached lists" style flow.
    func clear(key: String) {
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(Self.sanitize(key)).appendingPathExtension("json")
    }

    /// Filesystem-safe filename derived from an arbitrary cache key:
    /// URL-safe base64, so any characters a caller's key happens to contain
    /// (UUIDs, colons, resource-type names) round-trip without manual
    /// escaping or collision risk.
    private static func sanitize(_ key: String) -> String {
        Data(key.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
    }
}
