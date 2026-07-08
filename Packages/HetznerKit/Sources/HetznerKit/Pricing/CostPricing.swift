import Foundation

/// How a `CostItem` accrues cost over the course of a month.
///
/// All amounts are net (VAT excluded) `Decimal` values in the account's
/// billing currency. Never `Double` — money is exact decimal arithmetic.
public enum CostPricing: Sendable, Equatable {
    /// Billed per hour the resource exists, optionally capped at a monthly
    /// maximum (Hetzner caps most hourly resources so a full month of hourly
    /// billing never exceeds the equivalent monthly price).
    case hourly(net: Decimal, monthlyCap: Decimal?)

    /// Billed as a single flat amount for a full calendar month, prorated by
    /// elapsed/remaining time when the resource didn't exist for the whole
    /// month (e.g. primary IPs, some add-ons).
    case monthlyFlat(net: Decimal)
}
