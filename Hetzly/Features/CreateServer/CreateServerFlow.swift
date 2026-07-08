import HetznerKit
import SwiftUI

/// The app's "buy" flow: a single flowing sheet that walks through four
/// steps (location, image, type, configuration) and morphs its content in
/// place with `.snappy` transitions rather than pushing onto a
/// `NavigationStack`. Binding entry point per `CONTRACTS.md`'s M2 Wave B
/// contracts — presented with `.sheet(...) { CreateServerFlow(...) }` by
/// whichever screen offers "Create Server".
struct CreateServerFlow: View {
    let projectID: UUID
    let onCreated: (Server) -> Void

    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: CreateServerViewModel

    /// Server IDs with a root password saved in `ServerCredentialsVault` —
    /// refreshed on every appearance (cheap: a `UserDefaults` array read, no
    /// Keychain access) so step 1's banner reflects deletions made from its
    /// own sheet without needing a full flow relaunch.
    @State private var savedCredentialServerIDs: [Int] = []
    @State private var isSavedCredentialsSheetPresented = false

    init(projectID: UUID, onCreated: @escaping (Server) -> Void) {
        self.projectID = projectID
        self.onCreated = onCreated
        _viewModel = State(initialValue: CreateServerViewModel(projectID: projectID))
    }

    /// Preview/test-only entry point: injects a pre-populated view model so
    /// previews never touch the network or need a real `AppContainer` load.
    init(previewViewModel: CreateServerViewModel, onCreated: @escaping (Server) -> Void = { _ in }) {
        self.projectID = previewViewModel.projectID
        self.onCreated = onCreated
        _viewModel = State(initialValue: previewViewModel)
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            content
        }
        .interactiveDismissDisabled(viewModel.phase.isCreating)
        .task {
            guard viewModel.catalogState == .idle else { return }
            await viewModel.loadCatalog(container: container)
        }
        .onAppear {
            savedCredentialServerIDs = ServerCredentialsVault.knownServerIDs()
        }
        .sheet(isPresented: $isSavedCredentialsSheetPresented) {
            SavedCredentialsSheet(serverIDs: savedCredentialServerIDs) { serverID in
                ServerCredentialsVault.deleteRootPassword(serverID: serverID)
                savedCredentialServerIDs.removeAll { $0 == serverID }
                if savedCredentialServerIDs.isEmpty {
                    isSavedCredentialsSheetPresented = false
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .configuring:
            configuringContent
        case .creating, .succeeded, .failed:
            CreateServerResultView(
                viewModel: viewModel,
                onDone: { server in
                    onCreated(server)
                    dismiss()
                },
                onRetry: { viewModel.retryFromFailure() }
            )
        }
    }

    @ViewBuilder
    private var configuringContent: some View {
        switch viewModel.catalogState {
        case .idle, .loading:
            catalogLoadingView
        case .failed(let message):
            catalogFailedView(message)
        case .loaded:
            wizardContent
        }
    }

    private var catalogLoadingView: some View {
        VStack(spacing: Spacing.unit * 4) {
            if container.settings.mascotEnabled {
                MascotView(state: .idle, scale: 3)
            } else {
                ProgressView().controlSize(.large)
            }
            Text("Loading options…").caption()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func catalogFailedView(_ message: String) -> some View {
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
                Task { await viewModel.loadCatalog(container: container) }
            }
            .secondaryCTAStyle()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var wizardContent: some View {
        VStack(spacing: 0) {
            CreateServerStepHeader(
                step: viewModel.step,
                onBack: { withAnimation(.snappy) { viewModel.goBack() } },
                onCancel: { dismiss() }
            )
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.unit * 3)
            .padding(.bottom, Spacing.unit * 2)

            if viewModel.step == .location, !savedCredentialServerIDs.isEmpty {
                savedCredentialsBanner
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.bottom, Spacing.unit * 2)
            }

            ScrollView {
                stepContent
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.top, Spacing.unit * 2)
                    .padding(.bottom, Spacing.unit * 8)
            }

            CreateServerFooter(viewModel: viewModel) {
                if viewModel.step == .config {
                    Task { await viewModel.createServer(container: container) }
                } else {
                    withAnimation(.snappy) { viewModel.advance() }
                }
            }
        }
    }

    /// Step-1-only banner surfacing `ServerCredentialsVault`'s durable save:
    /// since this device stores every root password permanently (not just
    /// while the create flow's result screen is up), a later launch of this
    /// same flow is a natural, host-agnostic place to remind the user it's
    /// there — regardless of whether they ever navigate to that server's
    /// detail screen afterward.
    private var savedCredentialsBanner: some View {
        Button {
            isSavedCredentialsSheetPresented = true
        } label: {
            GlassCard {
                HStack(spacing: Spacing.unit * 3) {
                    Image(systemName: "key.fill")
                        .foregroundStyle(HetzlyColors.accent)
                    Text("The root password from your last server creation is saved on this device.")
                        .bodySecondary()
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(HetzlyColors.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var stepContent: some View {
        Group {
            switch viewModel.step {
            case .location: LocationStepView(viewModel: viewModel)
            case .image: ImageStepView(viewModel: viewModel)
            case .type: ServerTypeStepView(viewModel: viewModel)
            case .config: ConfigStepView(viewModel: viewModel)
            }
        }
        .id(viewModel.step)
        .transition(
            .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .trailing)),
                removal: .opacity.combined(with: .move(edge: .leading))
            )
        )
    }
}

/// Sheet behind `CreateServerFlow`'s step-1 banner: one `SensitiveSecretCard`
/// per server id with a durably-saved root password, plus an explicit
/// "Delete" action per card. Viewing here never deletes anything on its
/// own — `ServerCredentialsVault` only loses an entry when the user
/// deliberately asks it to, since these passwords are meant to stay
/// recoverable on this device indefinitely, not just until the next glance.
private struct SavedCredentialsSheet: View {
    let serverIDs: [Int]
    let onDelete: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.unit * 5) {
                        Text(
                            "These passwords are saved on this device so you never lose one just because a "
                                + "creation screen was dismissed. They stay here until you delete them."
                        )
                        .bodySecondary()

                        ForEach(serverIDs, id: \.self) { serverID in
                            if let secret = CreateServerViewModel.pendingSecret(forServerID: serverID) {
                                VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                                    SensitiveSecretCard(
                                        title: "Server #\(serverID) Root Password",
                                        secret: secret,
                                        note: "Saved on this device. Hetzner does not store this password — save it now if you haven't."
                                    )
                                    Button(role: .destructive) {
                                        onDelete(serverID)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .secondaryCTAStyle()
                                }
                            }
                        }
                    }
                    .padding(Spacing.screenMargin)
                }
            }
            .navigationTitle("Saved Passwords")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

#Preview("Step 1 — Location") {
    CreateServerFlow(previewViewModel: CreateServerPreviewFixtures.viewModel(step: .location))
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}

#Preview("Step 4 — Configure") {
    CreateServerFlow(previewViewModel: CreateServerPreviewFixtures.configuredViewModel())
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}

#Preview("Succeeded") {
    CreateServerFlow(previewViewModel: CreateServerPreviewFixtures.succeededViewModel(withRootPassword: true))
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}
