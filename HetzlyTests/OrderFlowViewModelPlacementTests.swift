import Foundation
import HetznerKit
import XCTest
@testable import Hetzly

/// Covers two correctness fixes to `OrderFlowViewModel.placeOrder`/
/// `retryPlacement`:
///
/// 1. **Double-fire guard**: `placeOrder` now starts with
///    `guard case .idle = placementPhase else { return }`. Real Face ID
///    authentication (`BiometricGate.authenticate`, backed by a real
///    `LAContext`) can't be driven to success in this sandboxed/headless
///    test environment — `canEvaluatePolicy` reliably reports no usable
///    device-owner authentication is configured — so these tests don't
///    attempt to race two live `Task { await viewModel.placeOrder(...) }`
///    calls through a real biometric prompt. Instead they model the state a
///    "second rapid tap" always observes: `placeOrder` flips `placementPhase`
///    away from `.idle` **synchronously, before its first `await`**, so by
///    the time a second call gets a turn on `OrderFlowViewModel`'s
///    `@MainActor` executor, the first call has *already* left `.idle` —
///    exactly the state seeded here. This is a faithful, deterministic
///    stand-in for "called twice rapidly" that doesn't depend on hardware.
/// 2. **Retry re-arm**: `retryPlacement()` forces `isArmed` back to `false`
///    for an ambiguous (transport-level/timeout) failure, but preserves it
///    for a clean API rejection — pure state logic, no network/Keychain
///    involved.
///
/// A `RobotClient` actor backed by a counting fake `HTTPTransport` is
/// injected via `OrderFlowViewModel`'s test-only `robotClientOverride` seam
/// so these tests can assert the network layer was never touched, without
/// any Keychain-stored Robot account.
@MainActor
final class OrderFlowViewModelPlacementTests: XCTestCase {
    /// Increments a counter on every `data(for:)` call, then throws — no
    /// production code path should ever be able to make placeOrder reach
    /// this once `placementPhase` is no longer `.idle` (or once `isArmed`/
    /// `draft` fail their guard), so a call here would fail the test loudly
    /// via the count assertion rather than needing a valid canned response.
    private actor CountingTransport: HTTPTransport {
        private(set) var callCount = 0

        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            callCount += 1
            throw HetznerAPIError.transport(underlying: "CountingTransport should never be invoked in this test")
        }
    }

    private func makeDraft() -> OrderDraft {
        .market(OrderPreviewFixtures.marketListings[0], sshKeys: [OrderPreviewFixtures.sshKeys[0]])
    }

    // MARK: - Double-fire guard

    /// The core regression test: a `placeOrder` call that arrives while
    /// `placementPhase` is already `.authenticating` (i.e. a prior call's
    /// Face ID prompt is still in flight) must be a complete no-op — no
    /// client call, no phase change — rather than re-entering and
    /// potentially placing a second real order.
    func test_placeOrder_whileAuthenticating_isNoOp() async {
        let transport = CountingTransport()
        let client = RobotClient(username: "test-user", password: "test-pass", transport: transport)
        let viewModel = OrderFlowViewModel(
            accountID: UUID(),
            accountUsername: "#123456",
            accountLabel: "Primary",
            draft: makeDraft(),
            placementPhase: .authenticating,
            robotClientOverride: client
        )
        viewModel.isArmed = true

        await viewModel.placeOrder(container: AppContainer.makeDefault())

        let callCount = await transport.callCount
        XCTAssertEqual(callCount, 0, "a call arriving mid-authentication must never touch the network")
        XCTAssertEqual(viewModel.placementPhase, .authenticating, "the in-flight phase must be left untouched")
    }

    /// Same guard, at the `.placing` phase — the window after Face ID
    /// succeeded but before the order's HTTP response has come back.
    func test_placeOrder_whilePlacing_isNoOp() async {
        let transport = CountingTransport()
        let client = RobotClient(username: "test-user", password: "test-pass", transport: transport)
        let viewModel = OrderFlowViewModel(
            accountID: UUID(),
            accountUsername: "#123456",
            accountLabel: "Primary",
            draft: makeDraft(),
            placementPhase: .placing,
            robotClientOverride: client
        )
        viewModel.isArmed = true

        await viewModel.placeOrder(container: AppContainer.makeDefault())

        let callCount = await transport.callCount
        XCTAssertEqual(callCount, 0, "a call arriving mid-placement must never touch the network")
        XCTAssertEqual(viewModel.placementPhase, .placing, "the in-flight phase must be left untouched")
    }

    /// Sanity check that the pre-existing armed/draft guards are unaffected
    /// by the new phase guard: from `.idle`, an unarmed call still never
    /// reaches the client either.
    func test_placeOrder_whenNotArmed_neverReachesClient() async {
        let transport = CountingTransport()
        let client = RobotClient(username: "test-user", password: "test-pass", transport: transport)
        let viewModel = OrderFlowViewModel(
            accountID: UUID(),
            accountUsername: "#123456",
            accountLabel: "Primary",
            draft: makeDraft(),
            placementPhase: .idle,
            robotClientOverride: client
        )
        viewModel.isArmed = false

        await viewModel.placeOrder(container: AppContainer.makeDefault())

        let callCount = await transport.callCount
        XCTAssertEqual(callCount, 0)
        XCTAssertEqual(viewModel.placementPhase, .idle)
    }

    // MARK: - Retry re-arm (fix 2)

    /// An ambiguous (transport-level/timeout) failure must force the user to
    /// re-confirm "I understand this is a real, paid order" before a retry
    /// can resubmit — `retryPlacement()` clears `isArmed`.
    func test_retryPlacement_afterAmbiguousFailure_forcesReArm() {
        let viewModel = OrderPreviewFixtures.reviewViewModel(
            phase: .failed(.message("A network error occurred. Please check your connection and try again.", isAmbiguous: true))
        )
        XCTAssertTrue(viewModel.isArmed, "fixture starts armed")

        viewModel.retryPlacement()

        XCTAssertFalse(viewModel.isArmed, "an ambiguous failure must force re-arming before a resubmit")
        XCTAssertEqual(viewModel.placementPhase, .idle)
    }

    /// A clean API rejection (e.g. out-of-stock) is safely retryable as-is —
    /// `retryPlacement()` must NOT force the user to re-toggle "I understand"
    /// for a straightforward, unambiguous rejection.
    func test_retryPlacement_afterCleanRejection_keepsArmed() {
        let viewModel = OrderPreviewFixtures.reviewViewModel(
            phase: .failed(.message("This product is temporarily out of stock."))
        )
        XCTAssertTrue(viewModel.isArmed, "fixture starts armed")

        viewModel.retryPlacement()

        XCTAssertTrue(viewModel.isArmed, "a clean rejection must not force re-arming")
        XCTAssertEqual(viewModel.placementPhase, .idle)
    }

    /// The ordering-disabled explainer card is its own case entirely (no
    /// `isAmbiguous` payload) — retrying it must also leave `isArmed` alone.
    func test_retryPlacement_afterOrderingDisabled_keepsArmed() {
        let viewModel = OrderPreviewFixtures.reviewViewModel(phase: .failed(.orderingDisabled))
        XCTAssertTrue(viewModel.isArmed, "fixture starts armed")

        viewModel.retryPlacement()

        XCTAssertTrue(viewModel.isArmed)
        XCTAssertEqual(viewModel.placementPhase, .idle)
    }
}
