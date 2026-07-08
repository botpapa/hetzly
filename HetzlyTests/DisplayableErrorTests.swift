import HetznerKit
import XCTest
@testable import Hetzly

/// Covers `DisplayableError`'s mapping from a thrown `Error` to a rendered
/// `message` plus the `isAuthError`/`isPermissionError` recovery flags —
/// the single source of truth every error-surfacing view model (Dashboard,
/// Resources, Costs, Dedicated, Server Detail) now feeds its "Update
/// token…" / "Update Token…" affordances from, replacing the old
/// string-matched-on-"token was rejected" approach.
final class DisplayableErrorTests: XCTestCase {
    func test_unauthorized_setsIsAuthErrorOnly() {
        let error = DisplayableError(HetznerAPIError.unauthorized)
        XCTAssertTrue(error.isAuthError)
        XCTAssertFalse(error.isPermissionError)
        XCTAssertEqual(error.message, "Your API token was rejected. It may have been revoked.")
    }

    func test_forbidden_setsIsPermissionErrorOnly_andIncludesReadOnlyGuidance() {
        let error = DisplayableError(HetznerAPIError.forbidden(message: nil))
        XCTAssertFalse(error.isAuthError)
        XCTAssertTrue(error.isPermissionError)
        XCTAssertTrue(error.message.contains("Read-only token"))
        XCTAssertTrue(error.message.contains("Read & Write token"))
    }

    func test_otherHetznerAPIError_setsNeitherFlag() {
        let error = DisplayableError(HetznerAPIError.notFound)
        XCTAssertFalse(error.isAuthError)
        XCTAssertFalse(error.isPermissionError)
        XCTAssertTrue(error.message.contains("could not be found"))
    }

    /// A non-`HetznerAPIError` (e.g. a decoding failure surfaced generically,
    /// or a plain `URLError`) falls back to a generic message with both
    /// flags `false` — there's no typed signal to key a recovery button off.
    func test_nonAPIError_fallsBackToGenericMessageWithNoFlags() {
        struct SomeOtherError: Error {}
        let error = DisplayableError(SomeOtherError())
        XCTAssertFalse(error.isAuthError)
        XCTAssertFalse(error.isPermissionError)
        XCTAssertEqual(error.message, "Something went wrong. Please try again.")
    }

    /// The direct `message:`/flags initializer, used by call sites that
    /// already have a resolved sentinel string (e.g. "No token configured
    /// for this project.") rather than a thrown `Error`.
    func test_directInit_carriesSuppliedMessageAndFlags() {
        let error = DisplayableError(message: "No token configured for this project.")
        XCTAssertEqual(error.message, "No token configured for this project.")
        XCTAssertFalse(error.isAuthError)
        XCTAssertFalse(error.isPermissionError)

        let flagged = DisplayableError(message: "custom", isAuthError: true, isPermissionError: false)
        XCTAssertTrue(flagged.isAuthError)
    }
}
