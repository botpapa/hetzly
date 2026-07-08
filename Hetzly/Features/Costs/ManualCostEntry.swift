import Foundation
import HetznerKit

/// A user-entered fixed monthly cost — chiefly for Hetzner Robot dedicated
/// servers, which have no Cloud API and can't be inventoried automatically
/// the way Cloud resources can. Stored locally (see `ManualCostStore`) and
/// fed into `CostEngine` alongside every project's live inventory so it
/// counts toward the combined Costs total.
///
/// This is the seed of the Robot integration landing in M3: once dedicated
/// servers can be listed for real, they'll replace manual entries with the
/// same `.dedicated` `CostKind` — the data model here is shaped to survive
/// that swap without a migration.
struct ManualCostEntry: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var name: String
    var monthlyPrice: Decimal
    var note: String?

    init(id: UUID = UUID(), name: String, monthlyPrice: Decimal, note: String? = nil) {
        self.id = id
        self.name = name
        self.monthlyPrice = monthlyPrice
        self.note = note
    }
}

extension ManualCostEntry {
    /// Adapts this entry into the pure `CostItem` shape `CostEngine`
    /// consumes: a flat monthly charge with no known creation date (nil
    /// means "existed before this month" — billed for the whole window,
    /// which is the right default for an ongoing fixed cost).
    var costItem: CostItem {
        CostItem(
            id: "manual-\(id.uuidString)",
            name: name,
            kind: .dedicated,
            pricing: .monthlyFlat(net: monthlyPrice),
            createdAt: nil
        )
    }
}
