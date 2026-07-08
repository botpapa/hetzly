import Foundation
import HetznerKit
import Observation

/// The two ordering surfaces Robot exposes, shown as a segmented control at
/// the top of `OrderServerFlow`.
enum OrderTab: String, CaseIterable, Identifiable, Sendable {
    case market, standard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .market: "Server Market"
        case .standard: "Standard"
        }
    }
}

/// Drives the market/standard browsing + ordering flow: loads the Server
/// Market / Standard catalogs and the account's SSH keys, holds
/// search/filter/sort UI state, assembles the `OrderDraft` a detail screen
/// hands to the review screen, and places the order (Face-ID-gated,
/// `test=false` set explicitly at that final step). Order history has its
/// own self-contained `TransactionsListView` rather than living here.
///
/// Deliberately does not store an `AppContainer` reference — `loadCatalog`
/// and `placeOrder` both take an `AppContainer` parameter, so preview/test
/// code can seed a fully-loaded instance (see `OrderPreviewFixtures`)
/// without touching the network. This mirrors `CreateServerViewModel`'s
/// convention.
@MainActor
@Observable
final class OrderFlowViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum PlacementPhase: Equatable {
        case idle
        case authenticating
        case placing
        case succeeded(TransactionSummary)
        case failed(OrderPlacementError)

        var isInFlight: Bool {
            switch self {
            case .authenticating, .placing: true
            default: false
            }
        }
    }

    let accountID: UUID
    let accountUsername: String
    let accountLabel: String

    // MARK: - Tab

    var selectedTab: OrderTab = .market

    // MARK: - Market

    private(set) var marketState: LoadState = .idle
    private(set) var marketListings: [MarketListing] = []
    var marketSearchText: String = ""
    var marketFilter = MarketFilter()
    var marketSort: MarketSort = .priceAscending
    var isMarketFilterPresented = false

    var filteredSortedMarketListings: [MarketListing] {
        let searched = search(marketListings, text: marketSearchText) { "\($0.name) \($0.cpu)" }
        let filtered = searched.filter(marketFilter.matches)
        return marketSort.sort(filtered)
    }

    // MARK: - Standard

    private(set) var standardState: LoadState = .idle
    private(set) var standardListings: [StandardListing] = []
    var standardSearchText: String = ""

    var filteredStandardListings: [StandardListing] {
        search(standardListings, text: standardSearchText) { "\($0.name) \($0.descriptionLines.joined(separator: " "))" }
    }

    // MARK: - SSH keys (required for every order — no password installs)

    private(set) var sshKeysState: LoadState = .idle
    private(set) var sshKeys: [SSHKeyOption] = []

    // MARK: - Draft (set by a detail view before pushing the review route)

    var draft: OrderDraft?

    // MARK: - Placement

    private(set) var placementPhase: PlacementPhase = .idle
    var isArmed = false

    /// Test-only seam: when set, `placeOrder` uses this `RobotClient`
    /// instead of resolving one from `container.robotClient(for: accountID)`
    /// — lets tests exercise the re-entrancy guard (and, with a fake
    /// `HTTPTransport` wired into a real `RobotClient`, the actual placement
    /// call count) without a Keychain-backed Robot account or a real
    /// `AppContainer`. `nil` in production; every production call site keeps
    /// resolving the client through `container` exactly as before.
    private let robotClientOverride: RobotClient?

    init(
        accountID: UUID,
        accountUsername: String,
        accountLabel: String,
        marketState: LoadState = .idle,
        marketListings: [MarketListing] = [],
        standardState: LoadState = .idle,
        standardListings: [StandardListing] = [],
        sshKeysState: LoadState = .idle,
        sshKeys: [SSHKeyOption] = [],
        draft: OrderDraft? = nil,
        placementPhase: PlacementPhase = .idle,
        robotClientOverride: RobotClient? = nil
    ) {
        self.accountID = accountID
        self.accountUsername = accountUsername
        self.accountLabel = accountLabel
        self.marketState = marketState
        self.marketListings = marketListings
        self.standardState = standardState
        self.standardListings = standardListings
        self.sshKeysState = sshKeysState
        self.sshKeys = sshKeys
        self.draft = draft
        self.placementPhase = placementPhase
        self.robotClientOverride = robotClientOverride
    }

    // MARK: - Catalog loading

    func loadCatalog(container: AppContainer) async {
        guard let client = container.robotClient(for: accountID) else {
            marketState = .failed("No stored credentials for this Robot account.")
            standardState = .failed("No stored credentials for this Robot account.")
            sshKeysState = .failed("No stored credentials for this Robot account.")
            return
        }
        async let marketTask: Void = loadMarketProducts(client: client)
        async let standardTask: Void = loadStandardProducts(client: client)
        async let sshTask: Void = loadSSHKeys(client: client)
        _ = await (marketTask, standardTask, sshTask)
    }

    func loadMarketProducts(container: AppContainer) async {
        guard let client = container.robotClient(for: accountID) else {
            marketState = .failed("No stored credentials for this Robot account.")
            return
        }
        await loadMarketProducts(client: client)
    }

    private func loadMarketProducts(client: RobotClient) async {
        marketState = .loading
        do {
            let products = try await client.listMarketProducts()
            marketListings = products.map(RobotOrderingMapping.listing)
            marketState = .loaded
        } catch {
            marketState = .failed(Self.message(for: error))
        }
    }

    func loadStandardProducts(container: AppContainer) async {
        guard let client = container.robotClient(for: accountID) else {
            standardState = .failed("No stored credentials for this Robot account.")
            return
        }
        await loadStandardProducts(client: client)
    }

    private func loadStandardProducts(client: RobotClient) async {
        standardState = .loading
        do {
            let products = try await client.listProducts()
            standardListings = products.map(RobotOrderingMapping.listing)
            standardState = .loaded
        } catch {
            standardState = .failed(Self.message(for: error))
        }
    }

    private func loadSSHKeys(client: RobotClient) async {
        sshKeysState = .loading
        do {
            let keys = try await client.listSSHKeys()
            sshKeys = keys.map(RobotOrderingMapping.option)
            sshKeysState = .loaded
        } catch {
            sshKeysState = .failed(Self.message(for: error))
        }
    }

    // MARK: - Placement

    func resetPlacement() {
        placementPhase = .idle
        isArmed = false
    }

    /// Clears a failure back to the idle review screen — used by the "Try
    /// Again" buttons in `OrderPlacementResultView`. For a clean API
    /// rejection (the request definitely reached Hetzner and was definitely
    /// refused) this doesn't force the user to re-toggle "I understand" for
    /// what's often a simple, safely-retryable hiccup. For a
    /// transport-level/timeout failure — where it's genuinely unknown
    /// whether the order went through — this forces `isArmed` back to
    /// `false` so a resubmit always requires a fresh, deliberate
    /// confirmation rather than blindly firing the same order again.
    func retryPlacement() {
        if case .failed(.message(_, let isAmbiguous)) = placementPhase, isAmbiguous {
            isArmed = false
        }
        placementPhase = .idle
    }

    /// The deliberate order-placement path (CONTRACTS.md, non-negotiable):
    /// review already happened in the UI, the armed toggle already gates the
    /// CTA — this method itself ALWAYS re-confirms with Face ID regardless of
    /// `AppSettings.requireBiometricsForDestructive` (this is real money, not
    /// a destructive action the user can opt out of confirming), and only
    /// then places the order with `test` explicitly flipped to `false`.
    ///
    /// Guarded against re-entrancy: this is real money, so a double-tap (or
    /// two fast taps registering before the CTA disables) must never fire
    /// two orders. `placementPhase` only leaves `.idle` synchronously, before
    /// the first `await`, so this check plus `@MainActor` serialization is
    /// enough to make a concurrent second call a no-op regardless of UI timing.
    func placeOrder(container: AppContainer) async {
        guard case .idle = placementPhase else { return }
        guard let draft, isArmed else { return }
        guard let client = robotClientOverride ?? container.robotClient(for: accountID) else {
            placementPhase = .failed(.message("No stored credentials for this Robot account."))
            return
        }

        placementPhase = .authenticating
        let approved = await container.biometricGate.authenticate(
            reason: "Confirm placing a paid order for \(draft.displayName)"
        )
        guard approved else {
            let reason = container.biometricGate.lastErrorMessage ?? "Authentication failed. Try again."
            placementPhase = .failed(.message(reason))
            return
        }

        placementPhase = .placing
        do {
            let transaction: RobotTransaction
            switch draft {
            case .market(let listing, let keys):
                // `RobotMarketOrder.test` defaults to `true` in the type
                // ("UI must explicitly set false") — this is the one
                // deliberate place in the app that overrides that default,
                // and only after the review + armed-toggle + Face ID gates
                // above have all passed. Market orders are as-is (no
                // location/dist parameter on the wire type).
                let order = RobotMarketOrder(
                    productID: listing.id,
                    authorizedKeys: keys.map(\.fingerprint),
                    test: false
                )
                transaction = try await client.orderMarketServer(order)
            case .standard(let listing, let price, let dist, let keys):
                // Same explicit override as above — `RobotServerOrder.test`
                // also defaults to `true` in the type.
                let order = RobotServerOrder(
                    productID: listing.id,
                    location: price.location,
                    dist: dist,
                    authorizedKeys: keys.map(\.fingerprint),
                    test: false
                )
                transaction = try await client.orderServer(order)
            }
            placementPhase = .succeeded(RobotOrderingMapping.summary(transaction))
        } catch {
            placementPhase = .failed(Self.placementError(for: error))
        }
    }

    // MARK: - Helpers

    private func search<T>(_ items: [T], text: String, key: (T) -> String) -> [T] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter { key($0).localizedCaseInsensitiveContains(trimmed) }
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? HetznerAPIError {
            return apiError.userMessage
        }
        return "Something went wrong. Please try again."
    }

    /// Robot's ordering-disabled case: 403 with the "NOT_ALLOWED"/ordering
    /// code preserved in `HetznerAPIError.forbidden(message:)` per
    /// CONTRACTS.md — routed to a dedicated explainer card instead of the
    /// generic failure copy.
    ///
    /// `.transport` is the one `HetznerAPIError` case that means "the
    /// request may never have reached Hetzner, or reached it but the
    /// response never made it back" — unlike every other case here, which
    /// means the server was definitely talked to and definitely gave a
    /// clean answer. Real money is on the line, so that ambiguity is flagged
    /// via `isAmbiguous` rather than treated like any other retryable error.
    private static func placementError(for error: Error) -> OrderPlacementError {
        if let apiError = error as? HetznerAPIError {
            if case .forbidden = apiError {
                return .orderingDisabled
            }
            if case .transport = apiError {
                return .message(message(for: error), isAmbiguous: true)
            }
        }
        return .message(message(for: error))
    }
}
