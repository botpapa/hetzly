import Foundation

/// A single billable resource fed into `CostEngine`. Pure input type — the
/// Pricing module intentionally does not import CloudAPI models; callers
/// (e.g. `CostItemBuilder`) adapt domain models into `CostItem` values.
public struct CostItem: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let kind: CostKind
    public let pricing: CostPricing
    /// When the underlying resource was created. `nil` means "existed before
    /// this month" (i.e. billed for the whole month window).
    public let createdAt: Date?

    public init(id: String, name: String, kind: CostKind, pricing: CostPricing, createdAt: Date? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.pricing = pricing
        self.createdAt = createdAt
    }
}
