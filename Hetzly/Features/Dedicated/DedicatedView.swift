import HetznerKit
import SwiftUI

/// Entry point for the Dedicated tab: an account-scoped list of Hetzner
/// Robot (dedicated) servers. Binding entry point per `CONTRACTS.md` — reads
/// `AppContainer` from the environment and owns its own `NavigationStack`
/// (the integrator wires this as the 5th tab; this file does not touch
/// `MainTabView`).
///
/// No auto-refresh timers, no background polling: the server list only
/// loads on first appearance, on account switch, and on explicit
/// pull-to-refresh (which force-bypasses `RobotClient`'s 5-minute cache).
struct DedicatedView: View {
    @Environment(AppContainer.self) private var container
    @State private var viewModel = DedicatedListViewModel()
    @State private var selectedAccountID: UUID?
    @State private var isPresentingOrderFlow = false

    init() {}

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()

                if container.robotAccountsStore.accounts.isEmpty {
                    noAccountsState
                } else {
                    content
                }
            }
            .navigationTitle("Dedicated")
            .navigationDestination(for: RobotServerRoute.self) { route in
                DedicatedServerDetailView(route: route)
            }
            .navigationDestination(isPresented: $isPresentingOrderFlow) {
                // Worker R4's binding entry point (Dedicated/Ordering/), per
                // CONTRACTS.md's M3 "App layer" section. Pass the currently
                // selected account when we have one so the order flow
                // doesn't have to re-derive "first configured account".
                if let selectedAccountID {
                    OrderServerFlow(accountID: selectedAccountID)
                } else {
                    OrderServerFlow()
                }
            }
            .toolbar {
                if container.robotAccountsStore.accounts.count > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        RobotAccountPickerChip(
                            accounts: container.robotAccountsStore.accounts,
                            selection: $selectedAccountID
                        )
                    }
                }
                if !container.robotAccountsStore.accounts.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isPresentingOrderFlow = true
                        } label: {
                            Label("Order Server", systemImage: "cart")
                        }
                    }
                }
            }
        }
        .task {
            if selectedAccountID == nil {
                selectedAccountID = container.robotAccountsStore.accounts.first?.id
            }
            await viewModel.load(accountID: selectedAccountID, container: container)
        }
        .onChange(of: selectedAccountID) { _, newValue in
            Task { await viewModel.load(accountID: newValue, container: container) }
        }
        .onChange(of: container.robotAccountsStore.accounts.map(\.id)) { _, ids in
            guard !ids.isEmpty else {
                selectedAccountID = nil
                return
            }
            if let selectedAccountID, !ids.contains(selectedAccountID) {
                self.selectedAccountID = ids.first
            } else if selectedAccountID == nil {
                selectedAccountID = ids.first
            }
        }
    }

    // MARK: - No accounts

    private var noAccountsState: some View {
        VStack(spacing: Spacing.unit * 5) {
            MascotView(state: .peek, scale: 4)
            VStack(spacing: Spacing.unit * 2) {
                SectionLabel("No Robot Accounts")
                Text("Add your Robot webservice account in Settings to see dedicated servers.")
                    .bodySecondary()
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.unit * 16)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            if viewModel.servers.isEmpty {
                ResourceLoadingState()
            } else {
                serverList
            }
        case .failed(let message):
            if viewModel.servers.isEmpty {
                VStack(spacing: Spacing.unit * 4) {
                    MascotView(state: .alarm, scale: 3)
                    Text(message)
                        .bodySecondary()
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.screenMargin * 2)
                    Button("Try Again") {
                        Task { await viewModel.load(accountID: selectedAccountID, container: container, forceRefresh: true) }
                    }
                    .secondaryCTAStyle()
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Spacing.unit * 16)
            } else {
                serverList
            }
        case .loaded:
            if viewModel.servers.isEmpty {
                emptyServersState
            } else {
                serverList
            }
        }
    }

    private var emptyServersState: some View {
        VStack(spacing: Spacing.unit * 5) {
            MascotView(state: .peek, scale: 4)
            VStack(spacing: Spacing.unit * 2) {
                SectionLabel("No Dedicated Servers")
                Text("This Robot account has no dedicated servers yet.")
                    .bodySecondary()
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.unit * 16)
    }

    @ViewBuilder
    private var serverList: some View {
        if let accountID = selectedAccountID {
            ScrollView {
                LazyVStack(spacing: Spacing.unit * 3) {
                    ForEach(viewModel.servers, id: \.serverNumber) { server in
                        NavigationLink(value: RobotServerRoute(accountID: accountID, serverNumber: server.serverNumber)) {
                            DedicatedServerRow(server: server)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.vertical, Spacing.screenMargin)
            }
            .refreshable {
                await viewModel.load(accountID: accountID, container: container, forceRefresh: true)
            }
        }
    }
}

#Preview {
    DedicatedView()
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}
