import Foundation

/// Result of running `CostEngine.summary(items:now:calendar:currency:)`.
/// Full precision `Decimal` values — rounding/formatting for display is the
/// UI layer's responsibility, not this engine's.
public struct CostSummary: Sendable, Equatable {
    /// Sum of every item's month-to-date accrual, from the start of the
    /// month (or the item's creation date if later) through `now`.
    public let monthToDate: Decimal
    /// Sum of every item's projected cost for the full calendar month.
    public let projectedMonthTotal: Decimal
    /// Per-item breakdown, sorted descending by `projectedMonth`.
    public let perItem: [ItemCost]
    public let currency: String

    public init(monthToDate: Decimal, projectedMonthTotal: Decimal, perItem: [ItemCost], currency: String) {
        self.monthToDate = monthToDate
        self.projectedMonthTotal = projectedMonthTotal
        self.perItem = perItem
        self.currency = currency
    }

    /// Per-`CostItem` cost breakdown.
    public struct ItemCost: Sendable, Identifiable, Equatable {
        public let id: String
        public let name: String
        public let kind: CostKind
        public let monthToDate: Decimal
        public let projectedMonth: Decimal

        public init(id: String, name: String, kind: CostKind, monthToDate: Decimal, projectedMonth: Decimal) {
            self.id = id
            self.name = name
            self.kind = kind
            self.monthToDate = monthToDate
            self.projectedMonth = projectedMonth
        }
    }
}
