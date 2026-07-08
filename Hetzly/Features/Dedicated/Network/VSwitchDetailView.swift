import HetznerKit
import SwiftUI

/// vSwitch detail: attached servers (with per-server ready/in-process/failed
/// status), read-only subnets + cloud networks, and rename/change-VLAN and
/// delete actions. Reads `AppContainer` from the environment and loads the
/// vSwitch for `route.accountID`/`route.vSwitchID` — `DedicatedView`
/// declares the `.navigationDestination(for: VSwitchRoute.self)` mapping
/// that lands here, mirroring `DedicatedServerDetailView`.
///
/// No auto-refresh timers, no background polling: every load happens either
/// once on first appearance or in direct response to a user action.
struct VSwitchDetailView: View {
    let route: VSwitchRoute

    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: VSwitchDetailViewModel?
    @State private var isPresentingEdit = false
    @State private var isPresentingAddServer = false
    @State private var pendingRemoveServer: RobotVSwitchServer?
    @State private var pendingDeleteConfirm = false
    @State private var isAuthenticatingDelete = false
    @State private var gateError: String?
    @State private var showSuccessToast = false
    @State private var successHaptic = false

    init(route: VSwitchRoute) {
        self.route = route
    }

    var body: some View {
        ZStack(alignment: .top) {
            CanvasBackground()
            body(for: viewModel)
            successToastOverlay
        }
        .navigationTitle(viewModel?.vSwitch?.name ?? "vSwitch")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let vSwitch = viewModel?.vSwitch {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isPresentingEdit = true
                        } label: {
                            Label("Rename / Change VLAN", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            pendingDeleteConfirm = true
                        } label: {
                            Label("Delete vSwitch", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(vSwitch.cancelled)
                }
            }
        }
        .task {
            guard viewModel == nil else { return }
            let model = VSwitchDetailViewModel(route: route, container: container)
            viewModel = model
            await model.load()
        }
        .sheet(isPresented: $isPresentingEdit) {
            if let vSwitch = viewModel?.vSwitch, let viewModel {
                VSwitchEditSheet(vSwitch: vSwitch, viewModel: viewModel)
            }
        }
        .sheet(isPresented: $isPresentingAddServer) {
            VSwitchAddServerSheet(
                availableServers: viewModel?.availableServersToAdd ?? [],
                state: viewModel?.accountServersState ?? .idle
            ) { numbers in
                viewModel?.addServers(numbers)
            }
        }
        .confirmationDialog(
            "Remove Server",
            isPresented: removeServerConfirmBinding,
            titleVisibility: .visible
        ) {
            Button("Remove from vSwitch", role: .destructive) { confirmRemoveServer() }
            Button("Cancel", role: .cancel) { pendingRemoveServer = nil }
        } message: {
            Text("Server \(pendingRemoveServer?.serverNumber ?? 0) will no longer be reachable over this VLAN.")
        }
        .sheet(isPresented: $pendingDeleteConfirm) {
            if let vSwitch = viewModel?.vSwitch {
                VSwitchDeleteConfirmSheet(
                    vSwitch: vSwitch,
                    isAuthenticating: isAuthenticatingDelete,
                    onConfirm: { confirmDelete() },
                    onCancel: { pendingDeleteConfirm = false }
                )
            }
        }
        .sensoryFeedback(.success, trigger: successHaptic)
        .onChange(of: viewModel?.lastActionSucceeded) { _, succeeded in
            guard succeeded == true else { return }
            handleActionSucceeded()
        }
        .onChange(of: viewModel?.didDelete) { _, deleted in
            guard deleted == true else { return }
            dismiss()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func body(for viewModel: VSwitchDetailViewModel?) -> some View {
        if let viewModel {
            switch viewModel.loadState {
            case .idle, .loading:
                if viewModel.vSwitch == nil {
                    loadingState
                } else {
                    loadedContent(viewModel)
                }
            case .failed(let message):
                if let vSwitch = viewModel.vSwitch {
                    loadedContent(viewModel, staleVSwitch: vSwitch)
                } else {
                    errorState(message)
                }
            case .loaded:
                loadedContent(viewModel)
            }
        } else {
            loadingState
        }
    }

    private var loadingState: some View {
        VStack(spacing: Spacing.unit * 4) {
            if container.settings.mascotEnabled {
                MascotView(state: .idle, scale: 3)
            } else {
                ProgressView().controlSize(.large)
            }
            Text("Loading vSwitch…").caption()
        }
    }

    private func errorState(_ message: String) -> some View {
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
                Task { await viewModel?.load() }
            }
            .secondaryCTAStyle()
        }
    }

    @ViewBuilder
    private func loadedContent(_ viewModel: VSwitchDetailViewModel, staleVSwitch: RobotVSwitch? = nil) -> some View {
        if let vSwitch = viewModel.vSwitch ?? staleVSwitch {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.unit * 8) {
                    heroCard(vSwitch)

                    if let actionError = viewModel.actionError {
                        Text(actionError)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(HetzlyColors.destructive)
                    }
                    if let gateError {
                        Text(gateError)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(HetzlyColors.destructive)
                    }
                    if viewModel.isPerformingAction {
                        HStack(spacing: Spacing.unit * 2) {
                            ProgressView().tint(HetzlyColors.textSecondary)
                            Text("Working…").caption()
                        }
                    }

                    serversSection(vSwitch)
                    subnetsSection(vSwitch)
                    cloudNetworksSection(vSwitch)
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.vertical, Spacing.unit * 6)
            }
            .refreshable { await viewModel.load() }
        }
    }

    private func heroCard(_ vSwitch: RobotVSwitch) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                HStack {
                    Text(vSwitch.name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(HetzlyColors.textPrimary)
                    Spacer()
                    if vSwitch.cancelled {
                        GlassChip("Cancelled")
                    }
                }
                HStack(spacing: Spacing.unit * 2) {
                    Text("VLAN")
                        .caption()
                    Text("\(vSwitch.vlan)")
                        .hetzlyMonoNumbers()
                        .foregroundStyle(HetzlyColors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Servers

    private func serversSection(_ vSwitch: RobotVSwitch) -> some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            HStack {
                SectionLabel("Servers")
                Spacer()
                Button {
                    Task { await viewModel?.loadAccountServers() }
                    isPresentingAddServer = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                }
                .disabled(vSwitch.cancelled)
            }

            let servers = vSwitch.servers
            if servers.isEmpty {
                GlassCard {
                    Text("No servers attached to this vSwitch yet.")
                        .bodySecondary()
                }
            } else {
                GlassCard {
                    VStack(spacing: 0) {
                        ForEach(Array(servers.enumerated()), id: \.element.serverNumber) { index, server in
                            if index > 0 {
                                Divider().overlay(HetzlyColors.textTertiary.opacity(0.2))
                            }
                            serverRow(server)
                        }
                    }
                }
            }
        }
    }

    private func serverRow(_ server: RobotVSwitchServer) -> some View {
        HStack(spacing: Spacing.unit * 3) {
            StatusDot(server.resourceStatus)
            VStack(alignment: .leading, spacing: 2) {
                Text("Server \(server.serverNumber)")
                    .bodyPrimary()
                if let ip = server.serverIP {
                    Text(ip).hetzlyMonoNumbers().font(.system(size: 12, design: .monospaced)).foregroundStyle(HetzlyColors.textTertiary)
                }
            }
            Spacer()
            Text(server.statusDisplayName)
                .caption()
        }
        .padding(.vertical, Spacing.unit)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingRemoveServer = server
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    // MARK: - Subnets / cloud networks

    @ViewBuilder
    private func subnetsSection(_ vSwitch: RobotVSwitch) -> some View {
        let subnets = vSwitch.subnets
        if !subnets.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                SectionLabel("Subnets")
                GlassCard {
                    VStack(spacing: 0) {
                        ForEach(Array(subnets.enumerated()), id: \.offset) { index, subnet in
                            if index > 0 {
                                Divider().overlay(HetzlyColors.textTertiary.opacity(0.2))
                            }
                            Text("\(subnet.ip)/\(subnet.mask)")
                                .hetzlyMonoNumbers()
                                .foregroundStyle(HetzlyColors.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, Spacing.unit)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cloudNetworksSection(_ vSwitch: RobotVSwitch) -> some View {
        let cloudNetworks = vSwitch.cloudNetworks
        if !cloudNetworks.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                SectionLabel("Cloud Networks")
                GlassCard {
                    VStack(spacing: 0) {
                        ForEach(Array(cloudNetworks.enumerated()), id: \.offset) { index, network in
                            if index > 0 {
                                Divider().overlay(HetzlyColors.textTertiary.opacity(0.2))
                            }
                            Text("\(network.ip)/\(network.mask)")
                                .hetzlyMonoNumbers()
                                .foregroundStyle(HetzlyColors.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, Spacing.unit)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var successToastOverlay: some View {
        if showSuccessToast, let text = viewModel?.lastActionSuccessText {
            ServerActionSuccessToast(text: text, mascotEnabled: container.settings.mascotEnabled)
                .padding(.top, Spacing.unit * 3)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Remove server

    private var removeServerConfirmBinding: Binding<Bool> {
        Binding(get: { pendingRemoveServer != nil }, set: { if !$0 { pendingRemoveServer = nil } })
    }

    private func confirmRemoveServer() {
        guard let server = pendingRemoveServer else { return }
        pendingRemoveServer = nil
        viewModel?.removeServer(server.serverNumber)
    }

    // MARK: - Delete gating

    private func confirmDelete() {
        guard let viewModel else { return }
        gateError = nil
        guard container.settings.requireBiometricsForDestructive else {
            pendingDeleteConfirm = false
            viewModel.delete()
            return
        }
        isAuthenticatingDelete = true
        Task {
            let reason = "Confirm deleting the vSwitch \(viewModel.vSwitch?.name ?? "")"
            let approved = await container.biometricGate.authenticate(reason: reason)
            isAuthenticatingDelete = false
            if approved {
                pendingDeleteConfirm = false
                viewModel.delete()
            } else {
                gateError = container.biometricGate.lastErrorMessage ?? "Authentication failed. Try again."
            }
        }
    }

    // MARK: - Success handling

    private func handleActionSucceeded() {
        successHaptic.toggle()
        withAnimation(.snappy) { showSuccessToast = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.snappy) { showSuccessToast = false }
            viewModel?.acknowledgeSuccess()
        }
    }
}

#Preview {
    NavigationStack {
        VSwitchDetailView(route: VSwitchRoute(accountID: UUID(), vSwitchID: NetworkPreviewFixtures.vSwitch.id))
            .environment(AppContainer.makeDefault())
    }
    .preferredColorScheme(.dark)
}
