import XCTest

/// Covers the "Pricing-accuracy + server-data" wave's Control-tab additions:
/// the hero card's IPv6 tap-to-copy row (added alongside the existing IPv4
/// one) and the Price row (tap opens `CloudServerPriceSheet`, PA's).
@MainActor
final class ServerPriceAndIPv6UITests: HetzlyUITestCase {
    func test_serverDetail_showsIPv6CopyRow_andPriceRowOpensSheet() {
        let app = launchSeeded()

        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 15))
        waitAndTap(element(labeled: "web-01", in: app))

        // Hero: IPv4 stays reachable, IPv6 is now a second tap-to-copy row
        // (every seeded server carries "2001:db8:1::/64" — see
        // `UITestSupport.serverJSON`). Tapping it should not crash (it
        // writes to the pasteboard and flips a local "copied" state).
        XCTAssertTrue(element(labeled: "95.216.1.10", in: app).waitForExistence(timeout: 10))
        let ipv6Row = element(labeled: "2001:db8:1::/64", in: app)
        XCTAssertTrue(ipv6Row.waitForExistence(timeout: 5), "IPv6 row should be reachable on the hero card")
        waitAndTap(ipv6Row)

        // Control tab (default): the Price row resolves a list price from
        // the seeded `/pricing` fixture (cx22 @ fsn1/nbg1/hel1 — see
        // `UITestSupport.pricingJSON`) and renders "<amount>/mo" — matched
        // on the literal "/mo" suffix rather than the currency-formatted
        // amount itself, since exact symbol/grouping is locale-dependent.
        let priceRow = element(labeled: "/mo", in: app)
        XCTAssertTrue(priceRow.waitForExistence(timeout: 5), "Price row should show a formatted monthly price")
        waitAndTap(priceRow)

        XCTAssertTrue(
            app.navigationBars["Set Price"].waitForExistence(timeout: 10)
                || app.navigationBars["Edit Price"].exists,
            "Tapping the Price row should open CloudServerPriceSheet"
        )
    }
}
