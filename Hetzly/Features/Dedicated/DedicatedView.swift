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
            .navigationDestination(for: VSwitchRoute.self) { route in
                VSwitchDetailView(route: route)
            }
            .navigationDestination(for: FailoverRoute.self) { route in
                FailoverDetailView(route: route)
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
            if container.settings.mascotEnabled {
                MascotView(state: .peek, scale: 4)
            } else {
                Image(systemName: "tray")
                    .font(.system(size: 40))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
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
                    if container.settings.mascotEnabled {
                        MascotView(state: .alarm, scale: 3)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(HetzlyColors.statusError)
                    }
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
            if container.settings.mascotEnabled {
                MascotView(state: .peek, scale: 4)
            } else {
                Image(systemName: "tray")
                    .font(.system(size: 40))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
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
                VStack(alignment: .leading, spacing: Spacing.unit * 8) {
                    LazyVStack(spacing: Spacing.unit * 3) {
                        ForEach(viewModel.servers, id: \.serverNumber) { server in
                            NavigationLink(value: RobotServerRoute(accountID: accountID, serverNumber: server.serverNumber)) {
                                DedicatedServerRow(server: server)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    networkSection(accountID: accountID)
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.vertical, Spacing.screenMargin)
            }
            .refreshable {
                await viewModel.load(accountID: accountID, container: container, forceRefresh: true)
            }
        }
    }

    /// vSwitch + Failover IP management — account-scoped, not tied to any
    /// particular dedicated server, so it lives below the server list rather
    /// than inside any one server's detail screen. Per CONTRACTS.md's
    /// "Robot vSwitch + failover (worker F2)" entry, the UI lives here in
    /// `Dedicated/Network/`.
    private func networkSection(accountID: UUID) -> some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            SectionLabel("Network")

            NavigationLink {
                VSwitchListView(accountID: accountID)
            } label: {
                networkRow(title: "vSwitches", systemImage: "square.split.2x2", subtitle: "Bridge servers onto a private VLAN")
            }
            .buttonStyle(.plain)

            NavigationLink {
                FailoverListView(accountID: accountID)
            } label: {
                networkRow(title: "Failover IPs", systemImage: "arrow.triangle.swap", subtitle: "Reroute an IP between servers")
            }
            .buttonStyle(.plain)
        }
    }

    private func networkRow(title: String, systemImage: String, subtitle: String) -> some View {
        GlassCard(interactive: true) {
            HStack(spacing: Spacing.unit * 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(HetzlyColors.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(HetzlyColors.textPrimary)
                    Text(subtitle)
                        .bodySecondary()
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    DedicatedView()
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}
