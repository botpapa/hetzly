import HetznerKit
import SwiftUI

/// Dedicated Server Detail: hero card (rename, IPs, traffic), Reset / Wake
/// on LAN actions, Rescue mode, read-only Boot Configuration, and Reverse
/// DNS. Reads `AppContainer` from the environment and loads the server for
/// `route.accountID` / `route.serverNumber` — `DedicatedView` declares the
/// `.navigationDestination(for: RobotServerRoute.self)` mapping that lands
/// here.
///
/// No auto-refresh timers, no background polling: every load happens either
/// once on first appearance or in direct response to a user action
/// (pull-to-refresh, opening a sheet, confirming an action).
struct DedicatedServerDetailView: View {
    let route: RobotServerRoute

    @Environment(AppContainer.self) private var container

    @State private var viewModel: DedicatedServerDetailViewModel?
    @State private var activeSheet: DetailSheet?
    @State private var isRenamePresented = false
    @State private var renameText = ""
    @State private var pendingWakeConfirm = false
    @State private var pendingDisableRescueConfirm = false
    /// Biometric failure surfaced outside a confirm sheet (reset/disable
    /// rescue gates run after their gathering sheet/dialog closes).
    @State private var gateError: String?
    @State private var showSuccessToast = false
    @State private var successHaptic = false

    private enum DetailSheet: Identifiable, Equatable {
        case reset
        case enableRescue
        case editRDNS(ip: String)

        var id: String {
            switch self {
            case .reset: "reset"
            case .enableRescue: "enableRescue"
            case .editRDNS(let ip): "editRDNS-\(ip)"
            }
        }
    }

    init(route: RobotServerRoute) {
        self.route = route
    }

    var body: some View {
        ZStack(alignment: .top) {
            CanvasBackground()
            body(for: viewModel)
            successToastOverlay
        }
        .navigationTitle(viewModel?.server?.displayName ?? "Server")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard viewModel == nil else { return }
            let model = DedicatedServerDetailViewModel(route: route, container: container)
            viewModel = model
            async let serverLoad: Void = model.load()
            async let resetLoad: Void = model.loadResetOptions()
            async let bootLoad: Void = model.loadBootConfiguration()
            async let rescueLoad: Void = model.loadRescue()
            _ = await (serverLoad, resetLoad, bootLoad, rescueLoad)
            await model.loadIPs()
            await model.loadRDNS()
        }
        .sheet(item: $activeSheet) { sheet in
            detailSheet(sheet)
        }
        .sheet(item: revealedRescuePasswordBinding) { revealed in
            DedicatedRescuePasswordSheet(
                password: revealed.password,
                onResetNow: { viewModel?.reset(type: .sw) },
                onDone: { viewModel?.dismissRevealedRescuePassword() }
            )
        }
        .alert("Rename Server", isPresented: $isRenamePresented) {
            TextField("hostname", text: $renameText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Save") { commitRename() }
                .disabled(!ServerDetailSupport.isValidHostname(renameText))
        } message: {
            Text("Letters, digits, hyphens and dots only (a valid hostname).")
        }
        .confirmationDialog("Wake on LAN", isPresented: $pendingWakeConfirm, titleVisibility: .visible) {
            Button("Send Wake-on-LAN") { viewModel?.wake() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sends a wake packet — for servers that are powered off.")
        }
        .confirmationDialog("Disable Rescue Mode", isPresented: $pendingDisableRescueConfirm, titleVisibility: .visible) {
            Button("Disable Rescue Mode", role: .destructive) { confirmDisableRescue() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The server will boot normally on its next restart.")
        }
        .sensoryFeedback(.success, trigger: successHaptic)
        .onChange(of: viewModel?.lastActionSucceeded) { _, succeeded in
            guard succeeded == true else { return }
            handleActionSucceeded()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func body(for viewModel: DedicatedServerDetailViewModel?) -> some View {
        if let viewModel {
            switch viewModel.loadState {
            case .idle, .loading:
                if viewModel.server == nil {
                    loadingState
                } else {
                    loadedContent(viewModel)
                }
            case .failed(let message):
                if let server = viewModel.server {
                    loadedContent(viewModel, staleServer: server)
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
            Text("Loading server…").caption()
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
    private func loadedContent(_ viewModel: DedicatedServerDetailViewModel, staleServer: RobotServer? = nil) -> some View {
        if let server = viewModel.server ?? staleServer {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.unit * 8) {
                    DedicatedServerHeroCard(server: server, onTapName: { beginRename(server) })

                    VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                        actionsRow
                        Text("Wake on LAN — for servers that are powered off.")
                            .caption()

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
                    }

                    DedicatedRescueSection(
                        rescue: viewModel.rescue,
                        rescueState: viewModel.rescueState,
                        onEnable: { openEnableRescueSheet() },
                        onDisable: { pendingDisableRescueConfirm = true }
                    )

                    DedicatedBootConfigSection(
                        bootConfiguration: viewModel.bootConfiguration,
                        state: viewModel.bootConfigState
                    )

                    DedicatedRDNSSection(
                        ips: viewModel.ips,
                        rdnsByIP: viewModel.rdnsByIP,
                        ipsState: viewModel.ipsState,
                        onEdit: { ip in activeSheet = .editRDNS(ip: ip) }
                    )
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.vertical, Spacing.unit * 6)
            }
            .refreshable { await refreshAll() }
        }
    }

    private var actionsRow: some View {
        HStack(spacing: Spacing.unit * 3) {
            Button {
                activeSheet = .reset
            } label: {
                Label("Reset", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .secondaryCTAStyle()
            .disabled(viewModel?.isPerformingAction ?? false)

            Button {
                pendingWakeConfirm = true
            } label: {
                Label("Wake on LAN", systemImage: "bolt")
                    .frame(maxWidth: .infinity)
            }
            .secondaryCTAStyle()
            .disabled(viewModel?.isPerformingAction ?? false)
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

    // MARK: - Sheets

    @ViewBuilder
    private func detailSheet(_ sheet: DetailSheet) -> some View {
        let serverName = viewModel?.server?.displayName ?? ""
        switch sheet {
        case .reset:
            ResetServerSheet(
                serverName: serverName,
                availableTypes: viewModel?.resetInfo?.availableTypes ?? [],
                resetInfoState: viewModel?.resetInfoState ?? .idle
            ) { type in
                presentAfterDismiss { handleResetSelection(type) }
            }
        case .enableRescue:
            EnableDedicatedRescueSheet(
                serverName: serverName,
                osOptions: DedicatedSupport.rescueOSOptions,
                sshKeys: viewModel?.sshKeys ?? [],
                sshKeysState: viewModel?.sshKeysState ?? .idle
            ) { os, fingerprints in
                presentAfterDismiss { viewModel?.enableRescue(os: os, sshKeyFingerprints: fingerprints) }
            }
        case .editRDNS(let ip):
            DedicatedRDNSEditSheet(ip: ip, currentPTR: viewModel?.rdnsByIP[ip]) { newPTR in
                if let newPTR {
                    _ = await viewModel?.setRDNS(ip: ip, ptr: newPTR)
                } else {
                    _ = await viewModel?.deleteRDNS(ip: ip)
                }
            }
        }
    }

    private func openEnableRescueSheet() {
        Task { await viewModel?.loadSSHKeys() }
        presentAfterDismiss { activeSheet = .enableRescue }
    }

    /// Chaining one sheet into another in the same tick races SwiftUI's
    /// dismissal animation and drops the second sheet. A short hop lets the
    /// outgoing sheet finish dismissing first (also harmless when nothing is
    /// currently presented — it's just a slightly delayed present).
    private func presentAfterDismiss(_ present: @escaping () -> Void) {
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            present()
        }
    }

    private var revealedRescuePasswordBinding: Binding<DedicatedServerDetailViewModel.RevealedRescuePassword?> {
        Binding(
            get: { viewModel?.revealedRescuePassword },
            set: { if $0 == nil { viewModel?.dismissRevealedRescuePassword() } }
        )
    }

    // MARK: - Action gating

    private func handleResetSelection(_ type: RobotResetType) {
        guard let viewModel else { return }
        gateError = nil
        guard type.isDestructive, container.settings.requireBiometricsForDestructive else {
            viewModel.reset(type: type)
            return
        }
        Task {
            let reason = "Confirm \(type.title.lowercased()) for \(viewModel.server?.displayName ?? "this server")"
            let approved = await container.biometricGate.authenticate(reason: reason)
            if approved {
                viewModel.reset(type: type)
            } else {
                gateError = container.biometricGate.lastErrorMessage ?? "Authentication failed. Try again."
            }
        }
    }

    private func confirmDisableRescue() {
        guard let viewModel else { return }
        gateError = nil
        guard container.settings.requireBiometricsForDestructive else {
            viewModel.disableRescue()
            return
        }
        Task {
            let reason = "Confirm disabling rescue mode for \(viewModel.server?.displayName ?? "this server")"
            let approved = await container.biometricGate.authenticate(reason: reason)
            if approved {
                viewModel.disableRescue()
            } else {
                gateError = container.biometricGate.lastErrorMessage ?? "Authentication failed. Try again."
            }
        }
    }

    // MARK: - Rename

    private func beginRename(_ server: RobotServer) {
        renameText = server.displayName
        isRenamePresented = true
    }

    private func commitRename() {
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ServerDetailSupport.isValidHostname(newName) else { return }
        Task { await viewModel?.rename(to: newName) }
    }

    // MARK: - Refresh

    private func refreshAll() async {
        guard let viewModel else { return }
        async let serverLoad: Void = viewModel.load(forceRefresh: true)
        async let resetLoad: Void = viewModel.loadResetOptions()
        async let bootLoad: Void = viewModel.loadBootConfiguration()
        async let rescueLoad: Void = viewModel.loadRescue()
        _ = await (serverLoad, resetLoad, bootLoad, rescueLoad)
        await viewModel.loadIPs()
        await viewModel.loadRDNS()
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
        DedicatedServerDetailView(route: RobotServerRoute(accountID: UUID(), serverNumber: DedicatedPreviewFixtures.server.serverNumber))
            .environment(AppContainer.makeDefault())
    }
    .preferredColorScheme(.dark)
}
