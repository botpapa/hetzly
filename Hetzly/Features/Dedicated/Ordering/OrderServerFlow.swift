import HetznerKit
import SwiftUI

/// Where `OrderServerFlow` can push next. Detail routes carry the listing's
/// `id` rather than the listing itself so the destination always reads the
/// current catalog from `viewModel` — see `OrderModels.swift`.
enum OrderRoute: Hashable {
    case marketDetail(id: String)
    case standardDetail(id: String)
    case review
    case transactions
}

/// The "buy a dedicated server" flow — pushed from `DedicatedView`'s toolbar
/// ("Order server", cart icon) per CONTRACTS.md's M3 Ordering UI contract.
/// Two tabs (Server Market / Standard), a product detail screen for each,
/// then the deliberate review → armed toggle → Face ID → place pipeline, and
/// a transactions list reachable via the toolbar clock icon.
///
/// Not its own `NavigationStack` — like `Dashboard` → `ServerDetailView` and
/// `DNSZoneListView` → `DNSZoneDetailView`, this registers its own
/// `.navigationDestination` and pushes via local `@State` item bindings, so
/// it composes correctly as a destination inside whatever `NavigationStack`
/// `DedicatedView` already owns.
struct OrderServerFlow: View {
    private enum Source {
        /// `accountID == nil` means "use the first configured Robot account".
        case live(accountID: UUID?)
        case preview(OrderFlowViewModel)
    }

    @Environment(AppContainer.self) private var container
    @State private var viewModel: OrderFlowViewModel?
    @State private var accountResolutionFailed = false
    @State private var pushedRoute: OrderRoute?

    private let source: Source

    /// Binding entry point per CONTRACTS.md: defaults to the account's first
    /// configured Robot account.
    init() {
        source = .live(accountID: nil)
    }

    /// Second entry point for callers that already know which Robot account
    /// they want (e.g. a `DedicatedView` with an active account picker).
    init(accountID: UUID) {
        source = .live(accountID: accountID)
    }

    /// Preview/test-only entry point: injects a pre-populated view model so
    /// previews never touch the network or a real `AppContainer` load path.
    init(previewViewModel: OrderFlowViewModel) {
        source = .preview(previewViewModel)
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            content
        }
        .navigationTitle("Order Server")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    pushedRoute = .transactions
                } label: {
                    Image(systemName: "clock")
                }
                .accessibilityLabel("Order History")
            }
        }
        .navigationDestination(item: $pushedRoute) { route in
            destination(for: route)
        }
        .task {
            await resolveAccountAndLoad()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let viewModel {
            VStack(spacing: 0) {
                Picker("Catalog", selection: Bindable(viewModel).selectedTab) {
                    ForEach(OrderTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.top, Spacing.unit * 3)
                .padding(.bottom, Spacing.unit * 2)

                switch viewModel.selectedTab {
                case .market:
                    MarketBrowserView(viewModel: viewModel) { id in pushedRoute = .marketDetail(id: id) }
                case .standard:
                    StandardProductListView(viewModel: viewModel) { id in pushedRoute = .standardDetail(id: id) }
                }
            }
        } else if accountResolutionFailed {
            noAccountState
        } else {
            VStack(spacing: Spacing.unit * 4) {
                if container.settings.mascotEnabled {
                    MascotView(state: .idle, scale: 3)
                } else {
                    ProgressView().controlSize(.large)
                }
                Text("Loading Robot account…").caption()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var noAccountState: some View {
        VStack(spacing: Spacing.unit * 4) {
            if container.settings.mascotEnabled {
                MascotView(state: .peek, scale: 3)
            } else {
                Image(systemName: "tray")
                    .font(.system(size: 40))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
            Text("No Robot account configured")
                .bodyPrimary()
                .fontWeight(.semibold)
            Text("Add a Robot account first — ordering bills to whichever account places the order.")
                .bodySecondary()
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.screenMargin * 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func destination(for route: OrderRoute) -> some View {
        if let viewModel {
            switch route {
            case .marketDetail(let id):
                if let listing = viewModel.marketListings.first(where: { $0.id == id }) {
                    MarketProductDetailView(listing: listing, sshKeys: viewModel.sshKeys) { draft in
                        viewModel.draft = draft
                        viewModel.resetPlacement()
                        pushedRoute = .review
                    }
                }
            case .standardDetail(let id):
                if let listing = viewModel.standardListings.first(where: { $0.id == id }) {
                    StandardProductDetailView(listing: listing, sshKeys: viewModel.sshKeys) { draft in
                        viewModel.draft = draft
                        viewModel.resetPlacement()
                        pushedRoute = .review
                    }
                }
            case .review:
                OrderReviewView(viewModel: viewModel) { pushedRoute = nil }
            case .transactions:
                TransactionsListView(accountID: viewModel.accountID)
            }
        }
    }

    // MARK: - Account resolution

    private func resolveAccountAndLoad() async {
        switch source {
        case .preview(let previewViewModel):
            viewModel = previewViewModel
            return
        case .live(let explicitAccountID):
            guard viewModel == nil else { return }
            let accounts = container.robotAccountsStore.accounts
            guard let account = explicitAccountID.flatMap({ id in accounts.first { $0.id == id } }) ?? accounts.first else {
                accountResolutionFailed = true
                return
            }
            let model = OrderFlowViewModel(
                accountID: account.id,
                accountUsername: account.username,
                accountLabel: account.label
            )
            viewModel = model
            await model.loadCatalog(container: container)
        }
    }
}

#Preview("Market") {
    NavigationStack {
        OrderServerFlow(previewViewModel: OrderPreviewFixtures.loadedViewModel())
            .environment(AppContainer.makeDefault())
    }
    .preferredColorScheme(.dark)
}

#Preview("Standard") {
    NavigationStack {
        OrderServerFlow(previewViewModel: OrderPreviewFixtures.loadedViewModel(tab: .standard))
            .environment(AppContainer.makeDefault())
    }
    .preferredColorScheme(.dark)
}
