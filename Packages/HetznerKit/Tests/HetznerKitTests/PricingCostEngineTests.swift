import Foundation
import Testing
@testable import HetznerKit

/// All fixtures use a fixed UTC `Calendar`/`Date` pair so the math never
/// depends on the wall clock or the host machine's timezone.
@Suite("CostEngine")
struct PricingCostEngineTests {
    // MARK: - Fixtures

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = TimeZone(identifier: "UTC")
        guard let result = utcCalendar.date(from: components) else {
            preconditionFailure("invalid fixture date")
        }
        return result
    }

    // MARK: - Hourly: mid-month accrual

    @Test func hourlyAccrualMidMonthWithFractionalHours() {
        // January has 31 days = 744 hours. "Now" is 15d 12h30m into the month.
        let now = Self.date(2024, 1, 16, 12, 30)
        let item = CostItem(
            id: "srv-1", name: "web-1", kind: .server,
            pricing: .hourly(net: Decimal(string: "0.0060")!, monthlyCap: nil),
            createdAt: nil
        )

        let summary = CostEngine.summary(items: [item], now: now, calendar: Self.utcCalendar, currency: "EUR")

        let expectedHoursElapsed = Decimal(372.5)
        let expectedMTD = expectedHoursElapsed * Decimal(string: "0.0060")!
        let expectedProjected = Decimal(744) * Decimal(string: "0.0060")!

        #expect(summary.monthToDate == expectedMTD)
        #expect(summary.projectedMonthTotal == expectedProjected)
        #expect(summary.perItem.count == 1)
        #expect(summary.perItem[0].monthToDate == expectedMTD)
        #expect(summary.perItem[0].projectedMonth == expectedProjected)
    }

    // MARK: - Hourly: monthly cap

    @Test func hourlyAccrualHitsMonthlyCapOnBothMTDAndProjection() {
        let now = Self.date(2024, 1, 16, 12) // 372h elapsed
        let cap = Decimal(string: "2.00")!
        let item = CostItem(
            id: "srv-2", name: "web-2", kind: .server,
            pricing: .hourly(net: Decimal(string: "0.0060")!, monthlyCap: cap),
            createdAt: nil
        )

        let summary = CostEngine.summary(items: [item], now: now, calendar: Self.utcCalendar, currency: "EUR")

        // Uncapped MTD would be 372 * 0.006 = 2.232 > cap, so both clamp to the cap.
        #expect(summary.monthToDate == cap)
        #expect(summary.projectedMonthTotal == cap)
    }

    @Test func hourlyAccrualBelowCapIsUnaffected() {
        let now = Self.date(2024, 1, 2, 0) // 24h elapsed
        let cap = Decimal(string: "10.00")!
        let item = CostItem(
            id: "srv-3", name: "web-3", kind: .server,
            pricing: .hourly(net: Decimal(string: "0.0060")!, monthlyCap: cap),
            createdAt: nil
        )

        let summary = CostEngine.summary(items: [item], now: now, calendar: Self.utcCalendar, currency: "EUR")

        let expectedMTD = Decimal(24) * Decimal(string: "0.0060")!
        #expect(summary.monthToDate == expectedMTD)
        #expect(summary.monthToDate < cap)
    }

    // MARK: - Hourly: resource created mid-month

    @Test func hourlyResourceCreatedMidMonthShiftsEffectiveStart() {
        let createdAt = Self.date(2024, 1, 10, 0)
        let now = Self.date(2024, 1, 16, 12)
        let item = CostItem(
            id: "srv-4", name: "web-4", kind: .server,
            pricing: .hourly(net: Decimal(string: "0.0060")!, monthlyCap: nil),
            createdAt: createdAt
        )

        let summary = CostEngine.summary(items: [item], now: now, calendar: Self.utcCalendar, currency: "EUR")

        // From Jan 10 00:00 to Jan 16 12:00 is 6d12h = 156h.
        let expectedMTD = Decimal(156) * Decimal(string: "0.0060")!
        // From Jan 10 00:00 to Feb 1 00:00 is 22d = 528h.
        let expectedProjected = Decimal(528) * Decimal(string: "0.0060")!

        #expect(summary.monthToDate == expectedMTD)
        #expect(summary.projectedMonthTotal == expectedProjected)
    }

    @Test func hourlyResourceCreatedBeforeMonthBehavesLikePreexisting() {
        let createdAt = Self.date(2023, 12, 1, 0)
        let now = Self.date(2024, 1, 2, 0)
        let item = CostItem(
            id: "srv-5", name: "web-5", kind: .server,
            pricing: .hourly(net: Decimal(string: "0.0060")!, monthlyCap: nil),
            createdAt: createdAt
        )

        let summary = CostEngine.summary(items: [item], now: now, calendar: Self.utcCalendar, currency: "EUR")

        let expectedMTD = Decimal(24) * Decimal(string: "0.0060")!
        #expect(summary.monthToDate == expectedMTD)
    }

    @Test func hourlyResourceCreatedInFutureAccruesNothingYet() {
        // Resource "created" later today than `now` (e.g. clock skew, or
        // scheduled activation) must not accrue negative/garbage cost.
        let now = Self.date(2024, 1, 5, 0)
        let createdAt = Self.date(2024, 1, 10, 0)
        let item = CostItem(
            id: "srv-6", name: "web-6", kind: .server,
            pricing: .hourly(net: Decimal(string: "0.0060")!, monthlyCap: nil),
            createdAt: createdAt
        )

        let summary = CostEngine.summary(items: [item], now: now, calendar: Self.utcCalendar, currency: "EUR")

        #expect(summary.monthToDate == 0)
        // Projection still counts from creation through month end: 22d = 528h.
        let expectedProjected = Decimal(528) * Decimal(string: "0.0060")!
        #expect(summary.projectedMonthTotal == expectedProjected)
    }

    // MARK: - Monthly flat: proration

    @Test func monthlyFlatProratesFromMidMonthCreation() {
        // April has 30 days. Created Apr 9 00:00, now Apr 16 00:00 (7d elapsed of a 22d remaining window).
        let createdAt = Self.date(2024, 4, 9, 0)
        let now = Self.date(2024, 4, 16, 0)
        let item = CostItem(
            id: "ip-1", name: "primary-ip", kind: .primaryIP,
            pricing: .monthlyFlat(net: Decimal(string: "6.00")!),
            createdAt: createdAt
        )

        let summary = CostEngine.summary(items: [item], now: now, calendar: Self.utcCalendar, currency: "EUR")

        // 6.00 * 7/30 = 1.4 exactly; 6.00 * 22/30 = 4.4 exactly.
        #expect(summary.monthToDate == Decimal(string: "1.4")!)
        #expect(summary.projectedMonthTotal == Decimal(string: "4.4")!)
    }

    @Test func monthlyFlatIsFullNetWhenPreexistingForWholeMonth() {
        let now = Self.date(2024, 4, 16, 0) // 15/30 elapsed
        let item = CostItem(
            id: "ip-2", name: "primary-ip-2", kind: .primaryIP,
            pricing: .monthlyFlat(net: Decimal(string: "5.00")!),
            createdAt: nil
        )

        let summary = CostEngine.summary(items: [item], now: now, calendar: Self.utcCalendar, currency: "EUR")

        #expect(summary.monthToDate == Decimal(string: "2.5")!)
        #expect(summary.projectedMonthTotal == Decimal(string: "5.00")!)
    }

    @Test func monthToDateIsZeroAtExactMonthStart() {
        let now = Self.date(2024, 1, 1, 0)
        let hourlyItem = CostItem(
            id: "srv-7", name: "web-7", kind: .server,
            pricing: .hourly(net: Decimal(string: "0.0060")!, monthlyCap: nil),
            createdAt: nil
        )
        let flatItem = CostItem(
            id: "ip-3", name: "primary-ip-3", kind: .primaryIP,
            pricing: .monthlyFlat(net: Decimal(string: "5.00")!),
            createdAt: nil
        )

        let summary = CostEngine.summary(
            items: [hourlyItem, flatItem], now: now, calendar: Self.utcCalendar, currency: "EUR"
        )

        #expect(summary.monthToDate == 0)
        #expect(summary.projectedMonthTotal > 0)
    }

    // MARK: - Aggregate behavior

    @Test func emptyItemsProduceZeroedSummary() {
        let now = Self.date(2024, 1, 16, 0)
        let summary = CostEngine.summary(items: [], now: now, calendar: Self.utcCalendar, currency: "EUR")

        #expect(summary.monthToDate == 0)
        #expect(summary.projectedMonthTotal == 0)
        #expect(summary.perItem.isEmpty)
        #expect(summary.currency == "EUR")
    }

    @Test func perItemIsSortedDescendingByProjectedCost() {
        let now = Self.date(2024, 1, 16, 0)
        let small = CostItem(
            id: "a", name: "small", kind: .volume,
            pricing: .monthlyFlat(net: Decimal(string: "1.00")!), createdAt: nil
        )
        let large = CostItem(
            id: "b", name: "large", kind: .server,
            pricing: .monthlyFlat(net: Decimal(string: "20.00")!), createdAt: nil
        )
        let medium = CostItem(
            id: "c", name: "medium", kind: .loadBalancer,
            pricing: .monthlyFlat(net: Decimal(string: "5.00")!), createdAt: nil
        )

        let summary = CostEngine.summary(
            items: [small, large, medium], now: now, calendar: Self.utcCalendar, currency: "EUR"
        )

        #expect(summary.perItem.map(\.id) == ["b", "c", "a"])
    }

    @Test func currencyPassesThroughUnmodified() {
        let now = Self.date(2024, 1, 16, 0)
        let summary = CostEngine.summary(items: [], now: now, calendar: Self.utcCalendar, currency: "USD")
        #expect(summary.currency == "USD")
    }
}
