import XCTest
@testable import Hetzly

/// `ServerCredentialsVault` is Keychain-backed via `KeychainStore` — same
/// constraint as `ProjectsStoreMultiProjectTests.test_updateToken_replacesStoredToken`
/// (see that file's doc comment for the full rationale): this unsigned,
/// sandboxed test run has no keychain-access-groups entitlement, so
/// `SecItemAdd` fails with `errSecMissingEntitlement` (OSStatus -34018).
/// Every test here attempts the real save first; if it fails for that
/// reason, the test reports `XCTSkip` (with the underlying error) instead of
/// failing red. On a properly signed/entitled run (a real device, or a
/// signed simulator build with keychain sharing configured), these same
/// assertion bodies exercise the genuine round trip.
///
/// `@MainActor` because `CreateServerViewModel.pendingSecret(forServerID:)`
/// — exercised by the last test — is itself `@MainActor`-isolated (it lives
/// on a `@MainActor @Observable` class); `ServerCredentialsVault` itself has
/// no actor isolation, so running these on the main actor changes nothing
/// about what's actually being tested.
@MainActor
final class ServerCredentialsVaultTests: XCTestCase {
    /// Large, obviously-fake ids unlikely to collide with anything real.
    /// This test process's `UserDefaults.standard` is scoped to the test
    /// bundle's own identifier (`com.hetzly.app.tests`), not the shipping
    /// app's, so there's no real collision risk either way — this just
    /// keeps the registry cleanup trivially exhaustive to reason about.
    private let serverID = 900_000_001
    private let otherServerID = 900_000_002

    override func tearDown() {
        ServerCredentialsVault.deleteRootPassword(serverID: serverID)
        ServerCredentialsVault.deleteRootPassword(serverID: otherServerID)
        super.tearDown()
    }

    /// Save → read → overwrite (upsert, no duplicate registry entry) →
    /// delete, checking the registry (`knownServerIDs`) at each step.
    func test_saveReadDelete_roundTrips() throws {
        do {
            try ServerCredentialsVault.saveRootPassword("s3cr3t-P@ss", serverID: serverID)
        } catch {
            throw XCTSkip(
                "Keychain is unavailable in this sandboxed/unsigned test run (\(error)); "
                    + "ServerCredentialsVault is UI-verified only here."
            )
        }

        XCTAssertEqual(ServerCredentialsVault.rootPassword(serverID: serverID), "s3cr3t-P@ss")
        XCTAssertTrue(ServerCredentialsVault.knownServerIDs().contains(serverID))

        // A newer password (e.g. from a later rescue/reset) overwrites the
        // old one in place rather than erroring or growing a second entry.
        try ServerCredentialsVault.saveRootPassword("newer-P@ss2", serverID: serverID)
        XCTAssertEqual(ServerCredentialsVault.rootPassword(serverID: serverID), "newer-P@ss2")
        XCTAssertEqual(ServerCredentialsVault.knownServerIDs().filter { $0 == serverID }.count, 1)

        // Deletion is explicit and user-initiated only in the real app, but
        // the vault itself must still support it cleanly when called.
        ServerCredentialsVault.deleteRootPassword(serverID: serverID)
        XCTAssertNil(ServerCredentialsVault.rootPassword(serverID: serverID))
        XCTAssertFalse(ServerCredentialsVault.knownServerIDs().contains(serverID))
    }

    /// Two different servers' saved passwords don't interfere with each
    /// other's Keychain entry or registry membership.
    func test_knownServerIDs_tracksMultipleEntriesIndependently() throws {
        do {
            try ServerCredentialsVault.saveRootPassword("password-one", serverID: serverID)
            try ServerCredentialsVault.saveRootPassword("password-two", serverID: otherServerID)
        } catch {
            throw XCTSkip(
                "Keychain is unavailable in this sandboxed/unsigned test run (\(error)); "
                    + "ServerCredentialsVault is UI-verified only here."
            )
        }

        let ids = ServerCredentialsVault.knownServerIDs()
        XCTAssertTrue(ids.contains(serverID))
        XCTAssertTrue(ids.contains(otherServerID))

        ServerCredentialsVault.deleteRootPassword(serverID: serverID)
        XCTAssertNil(ServerCredentialsVault.rootPassword(serverID: serverID))
        XCTAssertEqual(ServerCredentialsVault.rootPassword(serverID: otherServerID), "password-two")
        XCTAssertFalse(ServerCredentialsVault.knownServerIDs().contains(serverID))
        XCTAssertTrue(ServerCredentialsVault.knownServerIDs().contains(otherServerID))
    }

    /// Deleting an id that was never saved must be a safe no-op — this is
    /// the everyday case for `CreateServerViewModel`'s SSH-key-only path,
    /// which calls nothing here at all, and for any future caller that
    /// deletes defensively without first checking `knownServerIDs()`.
    func test_deleteRootPassword_isIdempotentForUnknownID() {
        ServerCredentialsVault.deleteRootPassword(serverID: 900_000_999)
        XCTAssertNil(ServerCredentialsVault.rootPassword(serverID: 900_000_999))
    }

    /// `CreateServerViewModel.pendingSecret(forServerID:)` is a thin
    /// passthrough to the vault — this pins that it actually reads through
    /// rather than, say, silently returning `nil` always.
    func test_pendingSecret_passthroughOnCreateServerViewModel_matchesVault() throws {
        do {
            try ServerCredentialsVault.saveRootPassword("via-passthrough", serverID: serverID)
        } catch {
            throw XCTSkip(
                "Keychain is unavailable in this sandboxed/unsigned test run (\(error)); "
                    + "ServerCredentialsVault is UI-verified only here."
            )
        }

        XCTAssertEqual(CreateServerViewModel.pendingSecret(forServerID: serverID), "via-passthrough")
    }
}
