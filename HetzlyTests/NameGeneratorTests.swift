import XCTest
@testable import Hetzly

/// `@MainActor` because `test_suggest_isValidAsAServerName` calls
/// `CreateServerViewModel.isValidServerName`, a static member of a
/// `@MainActor`-isolated class.
@MainActor
final class NameGeneratorTests: XCTestCase {
    /// `adjective-noun-NN`: lowercase words, single hyphens, a zero-padded
    /// two-digit numeric suffix in 01...99.
    private static let formatRegex = try! NSRegularExpression(pattern: "^[a-z]+-[a-z]+-[0-9]{2}$")

    func test_suggest_matchesExpectedFormat() {
        // Random word/suffix selection — sample many draws so a
        // format-breaking edge case (e.g. `Int.random(in: 1...99)`
        // formatting as one digit) would reliably surface.
        for _ in 0..<200 {
            let name = NameGenerator.suggest()
            let range = NSRange(name.startIndex..<name.endIndex, in: name)
            XCTAssertNotNil(
                Self.formatRegex.firstMatch(in: name, range: range),
                "\"\(name)\" doesn't match adjective-noun-NN"
            )
        }
    }

    func test_suggest_numericSuffixIsWithinBounds() {
        for _ in 0..<200 {
            let name = NameGenerator.suggest()
            let suffix = name.split(separator: "-").last.map(String.init)
            let value = suffix.flatMap { Int($0) }
            XCTAssertNotNil(value, "couldn't parse numeric suffix from \"\(name)\"")
            if let value {
                XCTAssertTrue((1...99).contains(value), "suffix \(value) out of bounds in \"\(name)\"")
            }
        }
    }

    func test_suggest_isValidAsAServerName() {
        // The generator's whole purpose is to prefill a name that passes the
        // wizard's own validity check without the user touching it.
        for _ in 0..<50 {
            let name = NameGenerator.suggest()
            XCTAssertTrue(
                CreateServerViewModel.isValidServerName(name),
                "\"\(name)\" isn't a valid server name"
            )
        }
    }
}
