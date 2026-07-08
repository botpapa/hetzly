import HetznerKit
import SwiftUI

/// Server Detail: hero card, contextual power actions (each gated behind a
/// confirmation sheet, destructive ones additionally behind Face ID/Touch ID
/// when the user has opted into that in Settings), METRICS charts, a light
/// Resources summary, and a collapsed Danger Zone.
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
    @State private var isAuthenticating = false
    @State private var authError: String?
    @State private var showSuccessToast = false
    @State private var successHaptic = false

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
        .task {
            guard viewModel == nil else { return }
            let model = ServerDetailViewModel(route: route, container: container)
            viewModel = model
            async let serverLoad: Void = model.load()
            async let metricsLoad: Void = model.loadMetrics()
            _ = await (serverLoad, metricsLoad)
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
        .sensoryFeedback(.success, trigger: successHaptic)
        .onChange(of: viewModel?.lastActionSucceeded) { _, succeeded in
            guard succeeded == true else { return }
            handleActionSucceeded()
        }
        .onChange(of: viewModel?.didDeleteServer) { _, deleted in
            guard deleted == true else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.1))
                dismiss()
            }
        }
    }

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
                        ServerActionRow(server: server) { action in
                            pendingAction = action
                        }

                        if let activeAction = viewModel.activeAction {
                            ServerActiveActionCard(
                                activeAction: activeAction,
                                mascotEnabled: container.settings.mascotEnabled
                            )
                        }

                        if let actionError = viewModel.actionError {
                            Text(actionError)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(HetzlyColors.destructive)
                        }
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

                    ServerDangerZoneSection {
                        pendingAction = .delete
                    }
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.vertical, Spacing.unit * 6)
            }
        }
    }

    @ViewBuilder
    private var successToastOverlay: some View {
        if showSuccessToast, let kind = viewModel?.lastSucceededAction {
            ServerActionSuccessToast(kind: kind, mascotEnabled: container.settings.mascotEnabled)
                .padding(.top, Spacing.unit * 3)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
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
        ServerDetailView(route: ServerRoute(projectID: UUID(), serverID: PreviewFixtures.server.id))
            .environment(AppContainer.makeDefault())
    }
    .preferredColorScheme(.dark)
}
