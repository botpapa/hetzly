import Foundation

/// Pure, deterministic month-to-date / projected cost math. No I/O, no
/// wall-clock reads — `now` and `calendar` are always supplied by the
/// caller, which is what makes this exhaustively unit-testable.
public enum CostEngine {
    /// Summarizes `items` over the calendar month (in `calendar`'s timezone)
    /// that contains `now`.
    ///
    /// - `.hourly(net:monthlyCap:)`: month-to-date accrual is the number of
    ///   hours elapsed between `max(monthStart, createdAt)` and `now`,
    ///   multiplied by `net`, capped at `monthlyCap` if present. The
    ///   projection uses the same math through the end of the month instead
    ///   of `now`.
    /// - `.monthlyFlat(net:)`: month-to-date is `net` multiplied by the
    ///   elapsed fraction of the (possibly createdAt-truncated) billing
    ///   window; the projection is `net` multiplied by the full fraction of
    ///   the month the item exists for (1.0 unless created mid-month).
    public static func summary(
        items: [CostItem],
        now: Date,
        calendar: Calendar,
        currency: String
    ) -> CostSummary {
        guard let monthInterval = calendar.dateInterval(of: .month, for: now) else {
            return CostSummary(monthToDate: 0, projectedMonthTotal: 0, perItem: [], currency: currency)
        }
        let monthStart = monthInterval.start
        let monthEnd = monthInterval.end // exclusive: start of next month

        var perItem: [CostSummary.ItemCost] = []
        perItem.reserveCapacity(items.count)
        var monthToDateTotal: Decimal = 0
        var projectedTotal: Decimal = 0

        for item in items {
            let effectiveStart = max(monthStart, item.createdAt ?? monthStart)
            let (mtd, projected) = costs(
                for: item.pricing,
                effectiveStart: effectiveStart,
                monthStart: monthStart,
                monthEnd: monthEnd,
                now: now,
                calendar: calendar
            )
            monthToDateTotal += mtd
            projectedTotal += projected
            perItem.append(
                CostSummary.ItemCost(
                    id: item.id,
                    name: item.name,
                    kind: item.kind,
                    monthToDate: mtd,
                    projectedMonth: projected
                )
            )
        }

        perItem.sort { $0.projectedMonth > $1.projectedMonth }

        return CostSummary(
            monthToDate: monthToDateTotal,
            projectedMonthTotal: projectedTotal,
            perItem: perItem,
            currency: currency
        )
    }

    // MARK: - Per-item math

    private static func costs(
        for pricing: CostPricing,
        effectiveStart: Date,
        monthStart: Date,
        monthEnd: Date,
        now: Date,
        calendar: Calendar
    ) -> (monthToDate: Decimal, projected: Decimal) {
        switch pricing {
        case .hourly(let net, let monthlyCap):
            let mtdEnd = clamp(now, lower: effectiveStart, upper: monthEnd)
            var mtd = net * hours(from: effectiveStart, to: mtdEnd, calendar: calendar)
            var projected = net * hours(from: effectiveStart, to: monthEnd, calendar: calendar)
            if let cap = monthlyCap {
                mtd = min(mtd, cap)
                projected = min(projected, cap)
            }
            return (mtd, projected)

        case .monthlyFlat(let net):
            let totalSeconds = seconds(from: monthStart, to: monthEnd, calendar: calendar)
            guard totalSeconds > 0 else { return (0, 0) }

            // Multiply before dividing so exact ratios (the common case for
            // real calendar/money inputs) don't get rounded away by an
            // intermediate repeating-decimal fraction.
            let mtdEnd = clamp(now, lower: effectiveStart, upper: monthEnd)
            let mtdSeconds = seconds(from: effectiveStart, to: mtdEnd, calendar: calendar)
            let mtd = (net * mtdSeconds) / totalSeconds

            let projectedSeconds = seconds(from: effectiveStart, to: monthEnd, calendar: calendar)
            let projected = (net * projectedSeconds) / totalSeconds

            return (mtd, projected)
        }
    }

    // MARK: - Helpers

    private static func clamp(_ date: Date, lower: Date, upper: Date) -> Date {
        min(max(date, lower), upper)
    }

    /// Whole seconds elapsed between `start` and `end`, as an exact
    /// `Decimal` (never negative). Uses `calendar` rather than
    /// `Date.timeIntervalSince` so the result is computed the same way
    /// everywhere the engine deals in elapsed time.
    private static func seconds(from start: Date, to end: Date, calendar: Calendar) -> Decimal {
        guard end > start else { return 0 }
        let elapsed = calendar.dateComponents([.second], from: start, to: end).second ?? 0
        return Decimal(max(0, elapsed))
    }

    private static func hours(from start: Date, to end: Date, calendar: Calendar) -> Decimal {
        seconds(from: start, to: end, calendar: calendar) / 3600
    }
}
