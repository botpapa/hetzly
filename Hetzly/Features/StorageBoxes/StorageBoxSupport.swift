import Foundation
import HetznerKit

/// Formatting and derivation helpers shared across the Storage Boxes
/// feature. Kept free of view code so it stays trivially testable, mirroring
/// `DedicatedSupport`/`ResourceFormatting` for the other feature areas.
///
/// - Note: `HetznerKit.StorageBox`'s exact shape is F1's `StorageBoxAPI`
///   contract (`CONTRACTS.md` → "Final-features wave contracts"). This file
///   was written against the documented Hetzner Storage Box API fields
///   (`status`, `stats.size`/`size_data`/`size_snapshots`,
///   `storage_box_type.size`, `access_settings.*`) — re-check against the
///   real package once it lands and adjust property names here rather than
///   scattered across views.
enum StorageBoxSupport {
    /// Formats a raw byte count (Hetzner reports Storage Box sizes in bytes)
    /// as a human string, e.g. "128.4 GB". A fresh `ByteCountFormatter` is
    /// built per call rather than cached in a `static let` — `Formatter`
    /// subclasses aren't uniformly `Sendable`-audited in the SDK, so a
    /// shared static instance trips Swift 6 strict concurrency; this
    /// mirrors `DedicatedSupport.paidUntilDisplay`'s local-`DateFormatter`
    /// pattern for the same reason.
    static func bytes(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: count)
    }

    static func dateString(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    static func dateTimeString(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Fraction of the box's total type size currently used, for the usage
    /// bar. `nil` when the type size is zero/unknown (never divide by zero).
    static func usageFraction(used: Int64, capacity: Int64) -> Double? {
        guard capacity > 0 else { return nil }
        return min(1, max(0, Double(used) / Double(capacity)))
    }
}

extension StorageBox {
    /// Maps Storage Box status to the DesignSystem's coarse `ResourceStatus`
    /// used by `StatusDot`.
    var resourceStatus: ResourceStatus {
        switch status {
        case .active: .running
        case .initializing: .transitioning
        case .locked: .error
        case .unknown: .unknown
        }
    }

    var statusDisplayName: String {
        switch status {
        case .active: "Active"
        case .initializing: "Initializing"
        case .locked: "Locked"
        case .unknown: "Unknown"
        }
    }
}
