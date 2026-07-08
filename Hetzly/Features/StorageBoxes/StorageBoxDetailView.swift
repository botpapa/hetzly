import HetznerKit
import SwiftUI

/// Storage Box Detail: hero card (rename, copyable username/hostname,
/// location, created), Usage, Access (protocol toggles), Snapshots,
/// Subaccounts, and a Danger Zone (reset password). Reads `AppContainer`
/// from the environment and loads the box for `route.accountID` /
/// `route.storageBoxID` — `StorageBoxesView` declares the
/// `.navigationDestination(for: StorageBoxRoute.self)` mapping that lands
/// here.
struct StorageBoxDetailView: View {
    let route: StorageBoxRoute

    @Environment(AppContainer.self) private var container

    @State private var viewModel: StorageBoxDetailViewModel?
    @State private var isRenamePresented = false
    @State private var renameText = ""
    @State private var isPresentingCreateSnapshot = false
    @State private var isPresentingCreateSubaccount = false
    @State private var pendingDeleteSnapshot: StorageBoxSnapshot?
    @State private var pendingDeleteSubaccount: StorageBoxSubaccount?
    @State private var pendingResetPassword = false
    @State private var gateError: String?
    @State private var showSuccessToast = false
    @State private var successHaptic = false

    init(route: StorageBoxRoute) {
        self.route = route
    }

    var body: some View {
        ZStack(alignment: .top) {
            CanvasBackground()
            body(for: viewModel)
            successToastOverlay
        }
        .navigationTitle(viewModel?.box?.name ?? "Storage Box")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard viewModel == nil else { return }
            let model = StorageBoxDetailViewModel(route: route, container: container)
            viewModel = model
            await model.load()
            async let snapshotsLoad: Void = model.loadSnapshots()
            async let subaccountsLoad: Void = model.loadSubaccounts()
            _ = await (snapshotsLoad, subaccountsLoad)
        }
        .alert("Rename Storage Box", isPresented: $isRenamePresented) {
            TextField("Name", text: $renameText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Save") { commitRename() }
                .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .sheet(isPresented: $isPresentingCreateSnapshot) {
            StorageBoxCreateSnapshotSheet { description in
                viewModel?.createSnapshot(description: description)
            }
        }
        .sheet(isPresented: $isPresentingCreateSubaccount) {
            CreateSubaccountSheet { homeDirectory, name, description, settings in
                viewModel?.createSubaccount(homeDirectory: homeDirectory, name: name, description: description, accessSettings: settings)
            }
        }
        .sheet(item: revealedPasswordBinding) { revealed in
            resetPasswordResultSheet(revealed)
        }
        .confirmationDialog(
            "Delete Snapshot",
            isPresented: pendingDeleteSnapshotBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { confirmDeleteSnapshot() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes this snapshot. It cannot be undone.")
        }
        .confirmationDialog(
            "Delete Subaccount",
            isPresented: pendingDeleteSubaccountBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { confirmDeleteSubaccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes this subaccount and revokes its access.")
        }
        .confirmationDialog(
            "Reset Password",
            isPresented: $pendingResetPassword,
            titleVisibility: .visible
        ) {
            Button("Reset Password", role: .destructive) { confirmResetPassword() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Generates a new password for this Storage Box. Anything using the old one loses access immediately.")
        }
        .sensoryFeedback(.success, trigger: successHaptic)
        .onChange(of: viewModel?.lastActionSucceeded) { _, succeeded in
            guard succeeded == true else { return }
            handleActionSucceeded()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func body(for viewModel: StorageBoxDetailViewModel?) -> some View {
        if let viewModel {
            switch viewModel.loadState {
            case .idle, .loading:
                if viewModel.box == nil {
                    loadingState
                } else {
                    loadedContent(viewModel)
                }
            case .failed(let message):
                if let box = viewModel.box {
                    loadedContent(viewModel, staleBox: box)
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
            Text("Loading Storage Box…").caption()
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
    private func loadedContent(_ viewModel: StorageBoxDetailViewModel, staleBox: StorageBox? = nil) -> some View {
        if let box = viewModel.box ?? staleBox {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.unit * 8) {
                    StorageBoxHeroCard(
                        box: box,
                        renameSupported: viewModel.renameSupported,
                        onTapName: { beginRename(box) }
                    )

                    if let actionError = viewModel.actionError {
                        ResourceErrorBanner(message: actionError)
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

                    StorageBoxUsageSection(box: box)

                    StorageBoxAccessSection(
                        settings: box.accessSettings,
                        supported: viewModel.accessSettingsSupported,
                        isPerformingAction: viewModel.isPerformingAction,
                        onToggle: { proto, enabled in viewModel.updateAccessSetting(proto, enabled: enabled) }
                    )

                    StorageBoxSnapshotsSection(
                        snapshots: viewModel.snapshots,
                        supported: viewModel.snapshotsSupported,
                        isPerformingAction: viewModel.isPerformingAction,
                        onCreateTapped: { isPresentingCreateSnapshot = true },
                        onDeleteTapped: { pendingDeleteSnapshot = $0 }
                    )

                    StorageBoxSubaccountsSection(
                        subaccounts: viewModel.subaccounts,
                        supported: viewModel.subaccountsSupported,
                        isPerformingAction: viewModel.isPerformingAction,
                        onCreateTapped: { isPresentingCreateSubaccount = true },
                        onDeleteTapped: { pendingDeleteSubaccount = $0 }
                    )

                    dangerZone(supported: viewModel.resetPasswordSupported, isPerformingAction: viewModel.isPerformingAction)
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.vertical, Spacing.unit * 6)
            }
            .refreshable { await refreshAll() }
        }
    }

    private func dangerZone(supported: Bool, isPerformingAction: Bool) -> some View {
        DisclosureGroup {
            GlassCard {
                Button(role: .destructive) {
                    pendingResetPassword = true
                } label: {
                    HStack {
                        Label("Reset Password", systemImage: "key.slash")
                            .foregroundStyle(supported ? HetzlyColors.destructive : HetzlyColors.textTertiary)
                        Spacer()
                    }
                    .padding(.vertical, Spacing.unit * 2)
                }
                .buttonStyle(.plain)
                .disabled(!supported || isPerformingAction)
            }
            .padding(.top, Spacing.unit * 3)
        } label: {
            Text("Danger Zone")
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(HetzlyColors.textTertiary)
        }
        .tint(HetzlyColors.textTertiary)
    }

    @ViewBuilder
    private func resetPasswordResultSheet(_ revealed: StorageBoxDetailViewModel.RevealedPassword) -> some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            Text(revealed.title).bodyPrimary().fontWeight(.semibold)
            if let subtitle = revealed.subtitle {
                Text(subtitle).hetzlyMonoNumbers().foregroundStyle(HetzlyColors.textSecondary)
            }
            SensitiveSecretCard(
                title: "Password",
                secret: revealed.password,
                note: "Shown once. Hetzner does not store this password — save it now."
            )
            Spacer(minLength: 0)
            Button("Done") { viewModel?.dismissRevealedPassword() }
                .secondaryCTAStyle()
                .frame(maxWidth: .infinity)
        }
        .padding(Spacing.screenMargin)
        .padding(.top, Spacing.unit * 2)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground { CanvasBackground() }
        .presentationCornerRadius(Radius.card)
        .interactiveDismissDisabled(false)
    }

    @ViewBuilder
    private var successToastOverlay: some View {
        if showSuccessToast, let text = viewModel?.lastActionSuccessText {
            ServerActionSuccessToast(text: text, mascotEnabled: container.settings.mascotEnabled)
                .padding(.top, Spacing.unit * 3)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Bindings

    private var revealedPasswordBinding: Binding<StorageBoxDetailViewModel.RevealedPassword?> {
        Binding(
            get: { viewModel?.revealedPassword },
            set: { if $0 == nil { viewModel?.dismissRevealedPassword() } }
        )
    }

    private var pendingDeleteSnapshotBinding: Binding<Bool> {
        Binding(get: { pendingDeleteSnapshot != nil }, set: { if !$0 { pendingDeleteSnapshot = nil } })
    }

    private var pendingDeleteSubaccountBinding: Binding<Bool> {
        Binding(get: { pendingDeleteSubaccount != nil }, set: { if !$0 { pendingDeleteSubaccount = nil } })
    }

    // MARK: - Rename

    private func beginRename(_ box: StorageBox) {
        renameText = box.name
        isRenamePresented = true
    }

    private func commitRename() {
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }
        Task { await viewModel?.rename(to: newName) }
    }

    // MARK: - Destructive confirmations (biometric-gated per Settings)

    private func confirmDeleteSnapshot() {
        guard let snapshot = pendingDeleteSnapshot, let viewModel else { return }
        pendingDeleteSnapshot = nil
        gateError = nil
        guard container.settings.requireBiometricsForDestructive else {
            viewModel.deleteSnapshot(snapshot)
            return
        }
        Task {
            let approved = await container.biometricGate.authenticate(reason: "Confirm deleting this snapshot")
            if approved {
                viewModel.deleteSnapshot(snapshot)
            } else {
                gateError = container.biometricGate.lastErrorMessage ?? "Authentication failed. Try again."
            }
        }
    }

    private func confirmDeleteSubaccount() {
        guard let subaccount = pendingDeleteSubaccount, let viewModel else { return }
        pendingDeleteSubaccount = nil
        gateError = nil
        guard container.settings.requireBiometricsForDestructive else {
            viewModel.deleteSubaccount(subaccount)
            return
        }
        Task {
            let approved = await container.biometricGate.authenticate(
                reason: "Confirm deleting subaccount \(subaccount.username)"
            )
            if approved {
                viewModel.deleteSubaccount(subaccount)
            } else {
                gateError = container.biometricGate.lastErrorMessage ?? "Authentication failed. Try again."
            }
        }
    }

    private func confirmResetPassword() {
        guard let viewModel else { return }
        gateError = nil
        guard container.settings.requireBiometricsForDestructive else {
            viewModel.resetPassword()
            return
        }
        Task {
            let approved = await container.biometricGate.authenticate(
                reason: "Confirm resetting the password for \(viewModel.box?.name ?? "this Storage Box")"
            )
            if approved {
                viewModel.resetPassword()
            } else {
                gateError = container.biometricGate.lastErrorMessage ?? "Authentication failed. Try again."
            }
        }
    }

    // MARK: - Refresh

    private func refreshAll() async {
        guard let viewModel else { return }
        await viewModel.load()
        async let snapshotsLoad: Void = viewModel.loadSnapshots()
        async let subaccountsLoad: Void = viewModel.loadSubaccounts()
        _ = await (snapshotsLoad, subaccountsLoad)
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
        StorageBoxDetailView(route: StorageBoxRoute(accountID: UUID(), storageBoxID: StorageBoxPreviewFixtures.box.id))
            .environment(AppContainer.makeDefault())
    }
    .preferredColorScheme(.dark)
}
