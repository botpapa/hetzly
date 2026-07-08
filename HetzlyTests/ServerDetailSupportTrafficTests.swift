import XCTest

@testable import Hetzly

/// Covers `ServerDetailSupport.trafficUsage(outgoing:ingoing:included:)` —
/// the Control tab's Traffic row formatter. Kept view-free per
/// `ServerDetailSupport`'s own "stays trivially testable" convention.
final class ServerDetailSupportTrafficTests: XCTestCase {
    func test_nilOutgoingAndIngoing_omitsTheRow() {
        let usage = ServerDetailSupport.trafficUsage(outgoing: nil, ingoing: nil, included: 21_990_232_555_520)
        XCTAssertNil(usage)
    }

    func test_formatsUsageLineAndIncludedLine() {
        // Round decimal byte counts (not binary GiB/TiB) since `bytes(_:)`
        // divides by decimal thresholds (1e9, 1e12, ...) — matches the
        // "1.2 TB out · 340 GB in" / "of 20 TB included" example from the
        // Server-page data wave contract.
        let usage = ServerDetailSupport.trafficUsage(
            outgoing: 1_200_000_000_000, // 1.2 TB
            ingoing: 340_000_000_000, // 340 GB
            included: 20_000_000_000_000 // 20 TB
        )
        XCTAssertEqual(usage?.usageLine, "1.2 TB out · 340.0 GB in")
        XCTAssertEqual(usage?.includedLine, "of 20.0 TB included")
    }

    func test_fractionAndPercentText_areComputedFromOutgoingOverIncluded() {
        let usage = ServerDetailSupport.trafficUsage(outgoing: 5_000_000_000, ingoing: 0, included: 10_000_000_000)
        XCTAssertEqual(usage?.fraction, 0.5)
        XCTAssertEqual(usage?.percentText, "50%")
    }

    func test_overIncludedTraffic_fractionExceedsOneRatherThanClamping() {
        let usage = ServerDetailSupport.trafficUsage(outgoing: 15_000_000_000, ingoing: 0, included: 10_000_000_000)
        XCTAssertEqual(usage?.fraction, 1.5)
        XCTAssertEqual(usage?.percentText, "150%")
    }

    func test_nilIncludedTraffic_omitsIncludedLineAndFractionButKeepsUsageLine() {
        let usage = ServerDetailSupport.trafficUsage(outgoing: 5_000_000_000, ingoing: 1_000_000_000, included: nil)
        XCTAssertNotNil(usage)
        XCTAssertNil(usage?.includedLine)
        XCTAssertNil(usage?.fraction)
        XCTAssertNil(usage?.percentText)
    }

    func test_zeroIncludedTraffic_treatedLikeMissingToAvoidDivisionByZero() {
        let usage = ServerDetailSupport.trafficUsage(outgoing: 5_000_000_000, ingoing: 0, included: 0)
        XCTAssertNil(usage?.includedLine)
        XCTAssertNil(usage?.fraction)
    }

    func test_onlyOneOfOutgoingIngoingReported_stillFormatsTheRow() {
        let usage = ServerDetailSupport.trafficUsage(outgoing: 1_000_000_000, ingoing: nil, included: nil)
        XCTAssertEqual(usage?.usageLine, "1.0 GB out · 0 B in")
    }
}
