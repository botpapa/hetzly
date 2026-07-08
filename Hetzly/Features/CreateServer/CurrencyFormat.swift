import Foundation

/// Formats `Decimal` money amounts using Hetzner's pricing currency code.
/// Defined locally in this feature (mirroring the shared style Costs uses)
/// rather than depending on another wave-B worker's in-flight module.
enum CurrencyFormat {
    /// e.g. `string(4.9, currencyCode: "EUR")` -> `"€4.90"`.
    static func string(_ amount: Decimal, currencyCode: String, fractionDigits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(currencyCode) \(amount)"
    }
}
