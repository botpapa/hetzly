import XCTest
@testable import Hetzly

/// Covers `DeepLinkParser.parse(_:)` — the sole entry point `HetzlyApp`'s
/// `.onOpenURL` (and its UI-test launch-environment bridge) route every
/// `hetzly://` URL through. Deliberately thorough per the module contract:
/// end-to-end `onOpenURL` UI testing isn't practical from `HetzlyUITests`
/// (XCTest has no supported API to simulate a real system URL-open
/// delivery), so this is the primary coverage for the parsing half of the
/// deep-link feature — `AppRouterTests` covers what happens after parsing.
final class DeepLinkParserTests: XCTestCase {
    private let projectID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let projectIDString = "00000000-0000-0000-0000-000000000001"

    // MARK: - server

    func test_server_parsesProjectAndServerID() throws {
        let url = try XCTUnwrap(URL(string: "hetzly://server/\(projectIDString)/42"))
        XCTAssertEqual(DeepLinkParser.parse(url), .server(ServerRoute(projectID: projectID, serverID: 42)))
    }

    func test_server_missingServerID_returnsNil() throws {
        let url = try XCTUnwrap(URL(string: "hetzly://server/\(projectIDString)"))
        XCTAssertNil(DeepLinkParser.parse(url))
    }

    func test_server_nonNumericServerID_returnsNil() throws {
        let url = try XCTUnwrap(URL(string: "hetzly://server/\(projectIDString)/not-a-number"))
        XCTAssertNil(DeepLinkParser.parse(url))
    }

    func test_server_malformedProjectID_returnsNil() throws {
        let url = try XCTUnwrap(URL(string: "hetzly://server/not-a-uuid/42"))
        XCTAssertNil(DeepLinkParser.parse(url))
    }

    func test_server_extraTrailingPathIsIgnored() throws {
        // Only the first two path segments matter — a widget/Shortcut built
        // against a hypothetical future extra segment shouldn't fail to
        // parse the part it already understands.
        let url = try XCTUnwrap(URL(string: "hetzly://server/\(projectIDString)/42/extra"))
        XCTAssertEqual(DeepLinkParser.parse(url), .server(ServerRoute(projectID: projectID, serverID: 42)))
    }

    // MARK: - project

    func test_project_parsesProjectID() throws {
        let url = try XCTUnwrap(URL(string: "hetzly://project/\(projectIDString)"))
        XCTAssertEqual(DeepLinkParser.parse(url), .project(ProjectRoute(projectID: projectID)))
    }

    func test_project_missingID_returnsNil() throws {
        let url = try XCTUnwrap(URL(string: "hetzly://project/"))
        XCTAssertNil(DeepLinkParser.parse(url))
    }

    func test_project_malformedID_returnsNil() throws {
        let url = try XCTUnwrap(URL(string: "hetzly://project/nope"))
        XCTAssertNil(DeepLinkParser.parse(url))
    }

    // MARK: - dashboard / costs

    func test_dashboard_parses() throws {
        let url = try XCTUnwrap(URL(string: "hetzly://dashboard"))
        XCTAssertEqual(DeepLinkParser.parse(url), .dashboard)
    }

    func test_costs_parses() throws {
        let url = try XCTUnwrap(URL(string: "hetzly://costs"))
        XCTAssertEqual(DeepLinkParser.parse(url), .costs)
    }

    // MARK: - scheme / host validation

    func test_wrongScheme_returnsNil() throws {
        let url = try XCTUnwrap(URL(string: "https://dashboard"))
        XCTAssertNil(DeepLinkParser.parse(url))
    }

    func test_unknownHost_returnsNil() throws {
        let url = try XCTUnwrap(URL(string: "hetzly://unknown"))
        XCTAssertNil(DeepLinkParser.parse(url))
    }

    func test_missingHost_returnsNil() throws {
        // "hetzly:///server/..." (empty host, path-only) — malformed, no
        // route to dispatch to.
        let url = try XCTUnwrap(URL(string: "hetzly:///dashboard"))
        XCTAssertNil(DeepLinkParser.parse(url))
    }

    func test_hostIsCaseInsensitive() throws {
        let url = try XCTUnwrap(URL(string: "hetzly://Dashboard"))
        XCTAssertEqual(DeepLinkParser.parse(url), .dashboard)
    }

    func test_schemeIsCaseInsensitive() throws {
        let url = try XCTUnwrap(URL(string: "HETZLY://costs"))
        XCTAssertEqual(DeepLinkParser.parse(url), .costs)
    }

    // MARK: - equatability sanity (Hashable-derived)

    func test_distinctServerRoutes_areNotEqual() {
        let a = DeepLink.server(ServerRoute(projectID: projectID, serverID: 1))
        let b = DeepLink.server(ServerRoute(projectID: projectID, serverID: 2))
        XCTAssertNotEqual(a, b)
    }
}
