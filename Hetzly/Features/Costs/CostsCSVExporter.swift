import Foundation
import HetznerKit

/// Builds a CSV export of the Costs tab's current numbers for the toolbar's
/// "Export CSV" action: one row per billable item across every project,
/// plus one row per priced dedicated server and manual entry (which — like
/// in `CostsViewModel` — aren't attached to any project section, so they're
/// grouped here under a synthetic "Dedicated" project label). Pure data
/// shaping + RFC 4180 quoting; the only I/O is the final write to a temp
/// file for `ShareLink`.
enum CostsCSVExporter {
    struct Row: Equatable {
        let project: String
        let itemName: String
        let kind: String
        let projectedMonthly: Decimal
        let monthToDate: Decimal
        let currency: String
    }

    // MARK: - Rows

    /// - Parameters:
    ///   - projectSections: `CostsViewModel.projectSections` — each section's
    ///     `itemCosts` becomes one row per item, `project` = section name.
    ///   - manualEntries: `ManualCostStore.entries`.
    ///   - dedicatedServers: `CostsViewModel.dedicatedServers` — only rows
    ///     with a set `monthlyPrice` are exported (an unpriced server has no
    ///     cost to report).
    static func rows(
        projectSections: [CostsViewModel.ProjectSection],
        manualEntries: [ManualCostEntry],
        dedicatedServers: [CostsViewModel.DedicatedServerRow],
        currency: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Row] {
        var rows: [Row] = []

        for section in projectSections {
            for item in section.itemCosts {
                rows.append(
                    Row(
                        project: section.projectName,
                        itemName: item.name,
                        kind: item.kind.rawValue,
                        projectedMonthly: item.projectedMonth,
                        monthToDate: item.monthToDate,
                        currency: currency
                    )
                )
            }
        }

        // Mirrors `CostsViewModel.dedicatedCostItems` / `ManualCostEntry.costItem`
        // exactly, then re-derives each item's projected/MTD split through the
        // same `CostEngine` math the combined total already uses — rather than
        // re-deriving proration by hand here.
        let dedicatedItems: [CostItem] = dedicatedServers.compactMap { row in
            guard let price = row.monthlyPrice else { return nil }
            return CostItem(id: row.id, name: row.name, kind: .dedicated, pricing: .monthlyFlat(net: price), createdAt: nil)
        }
        let manualItems = manualEntries.map(\.costItem)
        let combined = dedicatedItems + manualItems
        guard !combined.isEmpty else { return rows }

        let summary = CostEngine.summary(items: combined, now: now, calendar: calendar, currency: currency)
        for item in summary.perItem {
            rows.append(
                Row(
                    project: "Dedicated",
                    itemName: item.name,
                    kind: item.kind.rawValue,
                    projectedMonthly: item.projectedMonth,
                    monthToDate: item.monthToDate,
                    currency: currency
                )
            )
        }

        return rows
    }

    // MARK: - CSV rendering

    private static let header = ["Project", "Item", "Kind", "Projected Monthly", "Month to Date", "Currency"]

    /// RFC 4180: CRLF line endings, every field quoted (simplest correct
    /// implementation — no special-casing which fields "need" it), internal
    /// quotes doubled.
    static func csvString(rows: [Row]) -> String {
        var lines = [header.map(quote).joined(separator: ",")]
        for row in rows {
            let fields = [
                row.project,
                row.itemName,
                row.kind,
                decimalString(row.projectedMonthly),
                decimalString(row.monthToDate),
                row.currency,
            ]
            lines.append(fields.map(quote).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func quote(_ field: String) -> String {
        "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Machine-readable formatting: a `.` decimal point always, no thousands
    /// grouping, no currency symbol — locale-independent so the file parses
    /// the same way on any machine, per the export contract.
    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.decimalSeparator = "."
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static func decimalString(_ value: Decimal) -> String {
        numberFormatter.string(from: value as NSDecimalNumber) ?? "0.00"
    }

    // MARK: - File export

    /// Writes the CSV to a temp file named `hetzly-costs-<yyyy-MM>.csv`
    /// (overwriting any earlier export from the same month) and returns its
    /// URL for `ShareLink(item:)`.
    static func writeTempFile(rows: [Row], monthDate: Date = Date()) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        let filename = "hetzly-costs-\(formatter.string(from: monthDate)).csv"

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try csvString(rows: rows).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
