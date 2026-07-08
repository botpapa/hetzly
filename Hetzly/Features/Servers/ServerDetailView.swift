import HetznerKit
import SwiftUI

/// Server Detail: hero card, contextual power actions plus the "More"
/// management surface (each gated behind a confirmation sheet, sensitive
/// ones additionally behind Face ID/Touch ID when the user has opted into
/// that in Settings), PROTECTION row, METRICS charts, a light Resources
/// summary, BACKUPS & SNAPSHOTS, RESCUE MODE, and the Danger Zone
/// (Rebuild / Rescale / Delete).
///
/// Reads `AppContainer` from the environment and loads the server for
/// `route.projectID` / `route.serverID` — Worker D's Dashboard declares the
/// `.navigationDestination(for: ServerRoute.self) { ServerDetailView(route: $0) }`
/// mapping that lands here.
struct ServerDetailView: View {
    let route: ServerRoute

    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: ServerDetailViewModel?
    @State private var pendingAction: PowerAction?
    @State private var pendingManagementAction: ServerManagementAction?
    @State private var activeSheet: ManagementSheet?
    @State private var isAuthenticating = false
    @State private var authError: String?
    /// Biometric failure surfaced outside a confirm sheet (rescale flow).
    @State private var gateError: String?
    @State private var showSuccessToast = false
    @State private var toastIsManagement = false
    @State private var successHaptic = false
    @State private var isRenamePresented = false
    @State private var renameText = ""

    /// The parameter-gathering sheets this screen can present. Simple
    /// confirm-only actions go through `pendingManagementAction` instead.
    private enum ManagementSheet: Identifiable, Equatable {
        case more
        case createSnapshot
        case enableRescue
        case rebuild(preselected: HetznerKit.Image?)
        case rescale
        case iso
        case labels

        var id: String {
            switch self {
            case .more: "more"
            case .createSnapshot: "createSnapshot"
            case .enableRescue: "enableRescue"
            case .rebuild: "rebuild"
            case .rescale: "rescale"
            case .iso: "iso"
            case .labels: "labels"
            }
        }
    }

    init(route: ServerRoute) {
        self.route = route
    }

    var body: some View {
        ZStack(alignment: .top) {
            CanvasBackground()
            body(for: viewModel)
            successToastOverlay
        }
        .navigationTitle(viewModel?.server?.name ?? "Server")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarMenu }
        .task {
            guard viewModel == nil else { return }
            let model = ServerDetailViewModel(route: route, container: container)
            viewModel = model
            async let serverLoad: Void = model.load()
            async let metricsLoad: Void = model.loadMetrics()
            async let snapshotsLoad: Void = model.loadSnapshots()
            _ = await (serverLoad, metricsLoad, snapshotsLoad)
        }
        .sheet(item: $pendingAction) { action in
            ServerActionConfirmSheet(
                action: action,
                serverName: viewModel?.server?.name ?? "",
                isAuthenticating: isAuthenticating,
                authError: authError,
                onCancel: { pendingAction = nil; authError = nil },
                onConfirm: { confirm(action) }
            )
        }
        .sheet(item: $pendingManagementAction) { action in
            ServerManagementConfirmSheet(
                action: action,
                serverName: viewModel?.server?.name ?? "",
                isAuthenticating: isAuthenticating,
                authError: authError,
                onCancel: { pendingManagementAction = nil; authError = nil },
                onConfirm: { confirmManagement(action) }
            )
        }
        .sheet(item: $activeSheet) { sheet in
            managementSheet(sheet)
        }
        .sheet(item: revealedSecretBinding) { secret in
            SecretRevealSheet(
                secret: secret,
                onReboot: { viewModel?.runAction(.reboot) },
                onDone: { viewModel?.dismissRevealedSecret() }
            )
        }
        .sheet(item: consoleCredentialsBinding) { credentials in
            ConsoleCredentialsSheet(credentials: credentials) {
                viewModel?.dismissConsoleCredentials()
            }
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
        .sensoryFeedback(.success, trigger: successHaptic)
        .onChange(of: viewModel?.lastActionSucceeded) { _, succeeded in
            guard succeeded == true else { return }
            handleActionSucceeded(management: false)
        }
        .onChange(of: viewModel?.lastManagementActionSucceeded) { _, succeeded in
            guard succeeded == true else { return }
            handleActionSucceeded(management: true)
        }
        .onChange(of: viewModel?.didDeleteServer) { _, deleted in
            guard deleted == true else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.1))
                dismiss()
            }
        }
    }

    // MARK: - Toolbar

    private var toolbarMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    renameText = viewModel?.server?.name ?? ""
                    isRenamePresented = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button {
                    activeSheet = .labels
                } label: {
                    Label("Edit Labels", systemImage: "tag")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .disabled(viewModel?.server == nil)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func body(for viewModel: ServerDetailViewModel?) -> some View {
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
            MascotView(state: .idle, scale: 3)
            Text("Loading server…").caption()
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Spacing.unit * 4) {
            MascotView(state: .alarm, scale: 3)
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
    private func loadedContent(_ viewModel: ServerDetailViewModel, staleServer: Server? = nil) -> some View {
        if let server = viewModel.server ?? staleServer {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.unit * 8) {
                    ServerHeroCard(server: server)

                    VStack(alignment: .leading, spacing: Spacing.unit * 4) {
                        ServerActionRow(
                            server: server,
                            onSelect: { action in pendingAction = action },
                            onMore: { activeSheet = .more }
                        )

                        if let activeAction = viewModel.activeAction {
                            ServerActiveActionCard(
                                activeAction: activeAction,
                                mascotEnabled: container.settings.mascotEnabled
                            )
                        }

                        if let managementActiveAction = viewModel.managementActiveAction {
                            ServerActiveActionCard(
                                managementActiveAction: managementActiveAction,
                                mascotEnabled: container.settings.mascotEnabled
                            )
                        }

                        ForEach(inlineErrors, id: \.self) { message in
                            Text(message)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(HetzlyColors.destructive)
                        }
                    }

                    ServerProtectionRow(server: server) { enable in
                        pendingManagementAction = .changeProtection(delete: enable, rebuild: enable)
                    }

                    ServerMetricsSection(
                        metrics: viewModel.metrics,
                        state: viewModel.metricsState,
                        range: Binding(
                            get: { viewModel.selectedRange },
                            set: { viewModel.selectedRange = $0 }
                        )
                    )

                    ServerResourcesSection(server: server)

                    ServerBackupsSection(
                        server: server,
                        snapshots: viewModel.snapshots,
                        snapshotsState: viewModel.snapshotsState,
                        onToggleBackups: {
                            pendingManagementAction = server.backupWindow != nil ? .disableBackups : .enableBackups
                        },
                        onCreateSnapshot: { activeSheet = .createSnapshot },
                        onDeleteSnapshot: { snapshot in
                            Task { await viewModel.deleteSnapshot(snapshot) }
                        },
                        onRebuildFromSnapshot: { snapshot in
                            openRebuildSheet(preselected: snapshot)
                        }
                    )

                    ServerRescueSection(
                        server: server,
                        onEnable: { openEnableRescueSheet() },
                        onDisable: { pendingManagementAction = .disableRescue }
                    )

                    ServerDangerZoneSection(
                        protection: server.protection,
                        onRebuild: { openRebuildSheet(preselected: nil) },
                        onRescale: { openRescaleSheet() },
                        onDelete: { pendingAction = .delete }
                    )
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.vertical, Spacing.unit * 6)
            }
        }
    }

    /// Error strings shown under the action row: power-action errors,
    /// management errors, rename errors, and biometric failures that
    /// happened outside a confirm sheet.
    private var inlineErrors: [String] {
        [
            viewModel?.actionError,
            viewModel?.managementActionError,
            viewModel?.renameError,
            gateError,
        ].compactMap(\.self)
    }

    @ViewBuilder
    private var successToastOverlay: some View {
        if showSuccessToast {
            Group {
                if toastIsManagement, let text = viewModel?.lastManagementSuccessText {
                    ServerActionSuccessToast(text: text, mascotEnabled: container.settings.mascotEnabled)
                } else if let kind = viewModel?.lastSucceededAction {
                    ServerActionSuccessToast(kind: kind, mascotEnabled: container.settings.mascotEnabled)
                }
            }
            .padding(.top, Spacing.unit * 3)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Management sheets

    @ViewBuilder
    private func managementSheet(_ sheet: ManagementSheet) -> some View {
        let serverName = viewModel?.server?.name ?? ""
        switch sheet {
        case .more:
            if let server = viewModel?.server {
                ServerManagementMenuSheet(server: server) { selection in
                    handleMenuSelection(selection)
                }
            }
        case .createSnapshot:
            CreateSnapshotSheet(serverName: serverName) { description in
                viewModel?.runManagementAction(.createSnapshot(description: description))
            }
        case .enableRescue:
            EnableRescueSheet(
                serverName: serverName,
                sshKeys: viewModel?.sshKeys ?? [],
                sshKeysState: viewModel?.sshKeysState ?? .idle
            ) { keyIDs in
                presentAfterDismiss { pendingManagementAction = .enableRescue(sshKeyIDs: keyIDs) }
            }
        case .rebuild(let preselected):
            if let server = viewModel?.server {
                RebuildSheet(
                    server: server,
                    images: viewModel?.rebuildImages ?? [],
                    imagesState: viewModel?.rebuildImagesState ?? .idle,
                    preselected: preselected
                ) { image in
                    presentAfterDismiss { pendingManagementAction = .rebuild(image: image) }
                }
            }
        case .rescale:
            if let server = viewModel?.server {
                RescaleSheet(
                    server: server,
                    serverTypes: viewModel?.serverTypes ?? [],
                    serverTypesState: viewModel?.serverTypesState ?? .idle
                ) { serverType, upgradeDisk, powerOnAfter in
                    gateRescale(serverType: serverType, upgradeDisk: upgradeDisk, powerOnAfter: powerOnAfter)
                }
            }
        case .iso:
            ServerISOSheet(
                serverName: serverName,
                isos: viewModel?.isos ?? [],
                isosState: viewModel?.isosState ?? .idle,
                attachedISO: viewModel?.locallyAttachedISO,
                onAttach: { iso in
                    presentAfterDismiss { pendingManagementAction = .attachISO(iso: iso) }
                },
                onDetach: {
                    presentAfterDismiss { pendingManagementAction = .detachISO }
                }
            )
        case .labels:
            ServerLabelsEditorSheet(
                serverName: serverName,
                labels: viewModel?.server?.labels ?? [:],
                isSaving: viewModel?.isSavingLabels ?? false,
                saveError: viewModel?.labelsError,
                onSave: { labels in
                    Task {
                        if await viewModel?.updateLabels(labels) == true {
                            activeSheet = nil
                        }
                    }
                },
                onCancel: { activeSheet = nil }
            )
        }
    }

    private func handleMenuSelection(_ selection: ServerManagementMenuSheet.Selection) {
        guard let server = viewModel?.server else { return }
        switch selection {
        case .createSnapshot:
            presentAfterDismiss { activeSheet = .createSnapshot }
        case .toggleBackups:
            presentAfterDismiss {
                pendingManagementAction = server.backupWindow != nil ? .disableBackups : .enableBackups
            }
        case .toggleRescue:
            if server.rescueEnabled {
                presentAfterDismiss { pendingManagementAction = .disableRescue }
            } else {
                openEnableRescueSheet()
            }
        case .iso:
            openISOSheet()
        case .resetRootPassword:
            presentAfterDismiss { pendingManagementAction = .resetRootPassword }
        case .requestConsole:
            viewModel?.runManagementAction(.requestConsole)
        }
    }

    // MARK: - Sheet-opening helpers (kick off their data loads)

    private func openEnableRescueSheet() {
        Task { await viewModel?.loadSSHKeys() }
        presentAfterDismiss { activeSheet = .enableRescue }
    }

    private func openRebuildSheet(preselected: HetznerKit.Image?) {
        Task { await viewModel?.loadRebuildImages() }
        presentAfterDismiss { activeSheet = .rebuild(preselected: preselected) }
    }

    private func openRescaleSheet() {
        Task { await viewModel?.loadServerTypesAndPricing() }
        presentAfterDismiss { activeSheet = .rescale }
    }

    private func openISOSheet() {
        Task { await viewModel?.loadISOs() }
        presentAfterDismiss { activeSheet = .iso }
    }

    /// Chaining one sheet into another in the same tick races SwiftUI's
    /// dismissal animation and drops the second sheet. A short hop lets the
    /// outgoing sheet finish dismissing first. (Also harmless when nothing
    /// is currently presented — it's just a slightly delayed present.)
    private func presentAfterDismiss(_ present: @escaping () -> Void) {
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            present()
        }
    }

    // MARK: - Secret / console sheet bindings

    private var revealedSecretBinding: Binding<ServerDetailViewModel.RevealedSecret?> {
        Binding(
            get: { viewModel?.revealedSecret },
            set: { if $0 == nil { viewModel?.dismissRevealedSecret() } }
        )
    }

    private var consoleCredentialsBinding: Binding<ServerDetailViewModel.ConsoleCredentials?> {
        Binding(
            get: { viewModel?.consoleCredentials },
            set: { if $0 == nil { viewModel?.dismissConsoleCredentials() } }
        )
    }

    // MARK: - Action gating

    private func confirm(_ action: PowerAction) {
        guard let viewModel else { return }
        guard action.isDestructive, container.settings.requireBiometricsForDestructive else {
            fire(action, using: viewModel)
            return
        }

        isAuthenticating = true
        authError = nil
        Task {
            let reason = "Confirm \(action.title.lowercased()) for \(viewModel.server?.name ?? "this server")"
            let approved = await container.biometricGate.authenticate(reason: reason)
            isAuthenticating = false
            if approved {
                fire(action, using: viewModel)
            } else {
                authError = container.biometricGate.lastErrorMessage ?? "Authentication failed. Try again."
            }
        }
    }

    private func fire(_ action: PowerAction, using viewModel: ServerDetailViewModel) {
        pendingAction = nil
        authError = nil
        viewModel.runAction(action)
    }

    private func confirmManagement(_ action: ServerManagementAction) {
        guard let viewModel else { return }
        guard action.requiresBiometricGate, container.settings.requireBiometricsForDestructive else {
            fireManagement(action, using: viewModel)
            return
        }

        isAuthenticating = true
        authError = nil
        Task {
            let reason = "Confirm \(action.title.lowercased()) for \(viewModel.server?.name ?? "this server")"
            let approved = await container.biometricGate.authenticate(reason: reason)
            isAuthenticating = false
            if approved {
                fireManagement(action, using: viewModel)
            } else {
                authError = container.biometricGate.lastErrorMessage ?? "Authentication failed. Try again."
            }
        }
    }

    private func fireManagement(_ action: ServerManagementAction, using viewModel: ServerDetailViewModel) {
        pendingManagementAction = nil
        authError = nil
        viewModel.runManagementAction(action)
    }

    /// Rescale is in the biometric-gated set but its parameter sheet doubles
    /// as the confirm step, so the gate runs here (after the sheet closes)
    /// rather than inside a second confirm sheet. Failures surface inline
    /// under the action row via `gateError`.
    private func gateRescale(serverType: ServerType, upgradeDisk: Bool, powerOnAfter: Bool) {
        guard let viewModel else { return }
        gateError = nil
        guard container.settings.requireBiometricsForDestructive else {
            viewModel.runRescale(serverType: serverType, upgradeDisk: upgradeDisk, powerOnAfter: powerOnAfter)
            return
        }
        Task {
            let reason = "Confirm rescale to \(serverType.name) for \(viewModel.server?.name ?? "this server")"
            let approved = await container.biometricGate.authenticate(reason: reason)
            if approved {
                viewModel.runRescale(serverType: serverType, upgradeDisk: upgradeDisk, powerOnAfter: powerOnAfter)
            } else {
                gateError = container.biometricGate.lastErrorMessage ?? "Authentication failed. Try again."
            }
        }
    }

    // MARK: - Rename

    private func commitRename() {
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ServerDetailSupport.isValidHostname(newName) else { return }
        Task { await viewModel?.rename(to: newName) }
    }

    // MARK: - Success handling

    private func handleActionSucceeded(management: Bool) {
        successHaptic.toggle()
        toastIsManagement = management
        withAnimation(.snappy) { showSuccessToast = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.snappy) { showSuccessToast = false }
            if management {
                viewModel?.acknowledgeManagementSuccess()
            } else {
                viewModel?.acknowledgeSuccess()
            }
        }
    }
}

#Preview {
    NavigationStack {
        ServerDetailView(route: ServerRoute(projectID: UUID(), serverID: PreviewFixtures.server.id))
            .environment(AppContainer.makeDefault())
    }
    .preferredColorScheme(.dark)
}
