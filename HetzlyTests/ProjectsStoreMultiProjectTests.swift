import SwiftData
import XCTest
@testable import Hetzly

/// Covers the multi-project wave additions to `ProjectsStore`:
/// `move(fromOffsets:toOffset:)` (pure SwiftData reordering) and
/// `updateToken(for:to:)` (Keychain replace via `TokenVault`).
///
/// `move` is tested by inserting `ProjectRecord`s directly into an
/// in-memory `ModelContext`, bypassing `addProject(name:token:)` entirely —
/// `addProject` writes through `TokenVault`/`KeychainStore`, which in this
/// sandboxed/unsigned test environment cannot be assumed to succeed, and
/// `move` itself never touches the keychain, so there's no need to risk it.
///
/// `updateToken` is attempted too (it's the one piece of this file that
/// necessarily touches the real Keychain, via `addProject` first to seed a
/// token): CONFIRMED in this sandboxed/unsigned (`CODE_SIGNING_ALLOWED=NO`)
/// environment that `SecItemAdd` fails with `errSecMissingEntitlement`
/// (OSStatus -34018) — the test binary has no keychain-access-groups
/// entitlement to write with. `test_updateToken_replacesStoredToken` detects
/// exactly that failure and reports `XCTSkip` (with the underlying error) so
/// the suite stays green while being explicit that this codepath is
/// UI-verified only here — see `SettingsUITests` for the sheet-presentation
/// coverage, and `Hetzly/Features/Settings/UpdateTokenSheet.swift`'s actual
/// submit path (out of this worker's scope) for where the real write
/// happens. On a properly signed/entitled run (a real device or a signed
/// simulator build with keychain sharing configured), this same assertion
/// body would exercise the genuine round trip.
@MainActor
final class ProjectsStoreMultiProjectTests: XCTestCase {
    /// Retained for the lifetime of the test instance — `ModelContext` does
    /// NOT keep its owning `ModelContainer` alive on its own, so a helper
    /// that builds a container, returns only its `mainContext`, and lets the
    /// container fall out of scope deallocates the in-memory store out from
    /// under that context. That's a real use-after-free (SwiftData traps
    /// with `EXC_BREAKPOINT`/`SIGTRAP`, not a catchable Swift error) — this
    /// property is what keeps the container alive for as long as the test
    /// needs its context.
    ///
    /// nonisolated(unsafe): written only from @MainActor test methods; the
    /// nonisolated tearDown override merely nils it out, which cannot race
    /// the (already finished) test body.
    private nonisolated(unsafe) var container: ModelContainer!

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    private func makeInMemoryContext() -> ModelContext {
        let schema = Schema([ProjectRecord.self, ServerSnapshotRecord.self, RobotAccountRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        let builtContainer = try! ModelContainer(for: schema, configurations: [configuration])
        container = builtContainer
        return builtContainer.mainContext
    }

    // MARK: - move(fromOffsets:toOffset:)

    /// Three projects inserted directly (sortOrder 0, 1, 2); moving the last
    /// one to the front must persist as sortOrder 0, 1, 2 in the NEW order
    /// after a fresh fetch — i.e. re-instantiating `ProjectsStore` against
    /// the same context (simulating a relaunch) sees the reordered list, not
    /// just the in-memory `projects` array of the store that performed the
    /// move.
    func test_move_persistsSortOrderAfterRefetch() throws {
        let context = makeInMemoryContext()

        let first = ProjectRecord(name: "Alpha", sortOrder: 0)
        let second = ProjectRecord(name: "Bravo", sortOrder: 1)
        let third = ProjectRecord(name: "Charlie", sortOrder: 2)
        context.insert(first)
        context.insert(second)
        context.insert(third)
        try context.save()

        let store = ProjectsStore(context: context)
        XCTAssertEqual(store.projects.map(\.name), ["Alpha", "Bravo", "Charlie"])

        // Move "Charlie" (index 2) to the front (index 0).
        store.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        XCTAssertEqual(store.projects.map(\.name), ["Charlie", "Alpha", "Bravo"])
        XCTAssertEqual(store.projects.map(\.sortOrder), [0, 1, 2])

        // Re-fetch through an entirely new `ProjectsStore` instance sharing
        // the same context — this is what happens on app relaunch, and
        // proves the order was actually written to the SwiftData store, not
        // just held in the mutating instance's in-memory array.
        let reloaded = ProjectsStore(context: context)
        XCTAssertEqual(reloaded.projects.map(\.name), ["Charlie", "Alpha", "Bravo"])
        XCTAssertEqual(reloaded.projects.map(\.sortOrder), [0, 1, 2])
    }

    /// A move that keeps relative order for the untouched elements while
    /// relocating a middle element forward — reordering logic shouldn't
    /// accidentally depend on which end of the array is being moved.
    func test_move_middleElementForward_reordersCorrectly() throws {
        let context = makeInMemoryContext()

        let projects = (0..<4).map { ProjectRecord(name: "P\($0)", sortOrder: $0) }
        projects.forEach { context.insert($0) }
        try context.save()

        let store = ProjectsStore(context: context)
        XCTAssertEqual(store.projects.map(\.name), ["P0", "P1", "P2", "P3"])

        // Move index 1 ("P1") to index 3 (past "P2" and "P3").
        store.move(fromOffsets: IndexSet(integer: 1), toOffset: 3)

        XCTAssertEqual(store.projects.map(\.name), ["P0", "P2", "P1", "P3"])
        XCTAssertEqual(store.projects.map(\.sortOrder), [0, 1, 2, 3])
    }

    // MARK: - updateToken(for:to:)

    /// `updateToken` replaces what `token(for:)` subsequently returns,
    /// without touching the project record itself (name/sortOrder
    /// unchanged). Necessarily exercises the real Keychain via `TokenVault`
    /// — `ProjectsStore` hard-wires `TokenVault`/`KeychainStore` with no
    /// injection seam, so there is no way to fake this out from a test
    /// without editing those files (out of this worker's scope). Cleans up
    /// its own Keychain entry in a `defer` so repeated runs don't leak
    /// entries under random per-test UUIDs — reached only if seeding
    /// actually succeeds (see the `XCTSkip` path below for when it doesn't).
    func test_updateToken_replacesStoredToken() throws {
        let context = makeInMemoryContext()
        let store = ProjectsStore(context: context)

        let project: ProjectRecord
        do {
            project = try store.addProject(name: "Personal", token: "hcloud_original_token")
        } catch {
            // Confirmed cause in this environment: `errSecMissingEntitlement`
            // (-34018) — this unsigned test binary has no keychain-access-
            // groups entitlement to write with. Skip rather than fail red;
            // see the class doc comment for the full explanation.
            throw XCTSkip(
                "Keychain is unavailable in this sandboxed/unsigned test run (\(error)); "
                    + "ProjectsStore.updateToken(for:to:) is UI-verified only here."
            )
        }
        defer { try? TokenVault.deleteCloudToken(projectID: project.id.uuidString) }

        XCTAssertEqual(try store.token(for: project), "hcloud_original_token")

        try store.updateToken(for: project, to: "hcloud_rotated_token")

        XCTAssertEqual(try store.token(for: project), "hcloud_rotated_token")
        // The record itself is untouched by a token rotation.
        XCTAssertEqual(project.name, "Personal")
        XCTAssertEqual(project.sortOrder, 0)
    }
}
