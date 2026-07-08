import XCTest
@testable import Hetzly

final class ProjectNameSuggestionTests: XCTestCase {
    private func suggest(_ names: [String]) -> String {
        ProjectNameSuggestion.suggest(fromServerNames: names, fallback: "Project 7")
    }

    func test_emptyProject_usesFallback() {
        XCTAssertEqual(suggest([]), "Project 7")
        XCTAssertEqual(suggest(["", "  "]), "Project 7")
    }

    func test_singleServer_usesStem() {
        XCTAssertEqual(suggest(["giga-prod"]), "Giga")
        XCTAssertEqual(suggest(["backoffice"]), "Backoffice")
        XCTAssertEqual(suggest(["db2"]), "Db2")
    }

    func test_singleServer_ambiguousStem_fallsBack() {
        XCTAssertEqual(suggest(["a-01"]), "Project 7")
    }

    func test_commonPrefix_cutsAtSeparatorBoundary() {
        // Raw LCP is "web-0" — must trim to the whole component "web".
        XCTAssertEqual(suggest(["web-01", "web-02"]), "Web")
        XCTAssertEqual(suggest(["shop.api", "shop.worker", "shop.db"]), "Shop")
        XCTAssertEqual(suggest(["acme-prod-web", "acme-prod-db"]), "Acme-Prod")
    }

    func test_noSharedConvention_usesFirstStem() {
        XCTAssertEqual(suggest(["giga-prod", "unrelated-box"]), "Giga")
    }

    func test_prefixEqualToWholeName() {
        // One name IS the prefix of the other ("api" / "api-worker").
        XCTAssertEqual(suggest(["api", "api-worker"]), "Api")
    }
}
