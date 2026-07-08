import HetznerKit
import SwiftUI

/// Failover IP detail: current active server, the "Switch Routing" flow
/// (the money action — server picker → explicit confirm → biometrics,
/// always, regardless of the destructive-actions setting, because routing
/// changes are outage-grade → `switchFailover` → success toast), and a
/// destructive "Remove Routing" row (`DELETE /failover/{ip}`) that disables
/// routing entirely. `DedicatedView` declares the
/// `.navigationDestination(for: FailoverRoute.self)` mapping that lands
/// here, mirroring `VSwitchDetailView`.
struct FailoverDetailView: View {
    let route: FailoverRoute

    @Environment(AppContainer.self) private var container

    @State private var viewModel: FailoverDetailViewModel?
    @State private var isPresentingServerPicker = false
    @State private var pendingReroute: (server: RobotServer, ip: String)?
    @State private var isAuthenticatingReroute = false
    @State private var pendingRemoveRoutingConfirm = false
    @State private var gateError: String?
    @State private var showSuccessToast = false
    @State private var successHaptic = false

    init(route: FailoverRoute) {
        self.route = route
    }

    var body: some View {
        ZStack(alignment: .top) {
            CanvasBackground()
            body(for: viewModel)
            successToastOverlay
        }
        .navigationTitle(route.ip)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard viewModel == nil else { return }
            let model = FailoverDetailViewModel(route: route, container: container)
            viewModel = model
            await model.load()
        }
        .sheet(isPresented: $isPresentingServerPicker) {
            FailoverSwitchRoutingSheet(
                failoverIP: route.ip,
                accountServers: viewModel?.accountServers ?? [],
                state: viewModel?.accountServersState ?? .idle
            ) { server, ip in
                presentAfterDismiss { pendingReroute = (server, ip) }
            }
        }
        .sheet(item: pendingRerouteBinding) { pending in
            FailoverRerouteConfirmSheet(
                failoverIP: route.ip,
                targetServerName: pending.server.displayName,
                targetIP: pending.ip,
                isAuthenticating: isAuthenticatingReroute,
                onConfirm: { confirmReroute(to: pending.ip) },
                onCancel: { pendingReroute = nil }
            )
        }
        .confirmationDialog(
            "Remove Routing",
            isPresented: $pendingRemoveRoutingConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove Routing", role: .destructive) { confirmRemoveRouting() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Disables routing for \(route.ip) — it stops receiving traffic until you switch it to a server again. Face ID / passcode is required.")
        }
        .sensoryFeedback(.success, trigger: successHaptic)
        .onChange(of: viewModel?.lastActionSucceeded) { _, succeeded in
            guard succeeded == true else { return }
            handleActionSucceeded()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func body(for viewModel: FailoverDetailViewModel?) -> some View {
        if let viewModel {
            switch viewModel.loadState {
            case .idle, .loading:
                if viewModel.failover == nil {
                    loadingState
                } else {
                    loadedContent(viewModel)
                }
            case .failed(let message):
                if let failover = viewModel.failover {
                    loadedContent(viewModel, staleFailover: failover)
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
            Text("Loading failover IP…").caption()
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
    private func loadedContent(_ viewModel: FailoverDetailViewModel, staleFailover: RobotFailover? = nil) -> some View {
        if let failover = viewModel.failover ?? staleFailover {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.unit * 8) {
                    heroCard(failover)

                    if let switchError = viewModel.switchError {
                        Text(switchError)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(HetzlyColors.destructive)
                    }
                    if let gateError {
                        Text(gateError)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(HetzlyColors.destructive)
                    }
                    if viewModel.isSwitching {
                        HStack(spacing: Spacing.unit * 2) {
                            ProgressView().tint(HetzlyColors.textSecondary)
                            Text("Switching…").caption()
                        }
                    }

                    actionsSection(failover)
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.vertical, Spacing.unit * 6)
            }
            .refreshable { await viewModel.load() }
        }
    }

    private func heroCard(_ failover: RobotFailover) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                SectionLabel("Failover IP")
                Text(failover.ip)
                    .hetzlyMonoNumbers()
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(HetzlyColors.textPrimary)

                Divider().overlay(HetzlyColors.textTertiary.opacity(0.15))

                DetailInfoRow(label: "Currently routed to", value: failover.activeServerIP ?? "—", monospaced: true)
                DetailInfoRow(label: "Home server", value: failover.serverIP, monospaced: true)
                DetailInfoRow(label: "Netmask", value: failover.netmask, monospaced: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func actionsSection(_ failover: RobotFailover) -> some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Switch Routing")
            Text("Reroute traffic for this IP to a different dedicated server on this account.")
                .caption()

            PrimaryCTA(title: "Switch Routing…") {
                Task { await viewModel?.loadAccountServers() }
                isPresentingServerPicker = true
            }
            .disabled(viewModel?.isSwitching ?? false)

            Button {
                pendingRemoveRoutingConfirm = true
            } label: {
                Label("Remove Routing", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .secondaryCTAStyle()
            .foregroundStyle(HetzlyColors.destructive)
            .disabled((viewModel?.isSwitching ?? false) || failover.activeServerIP == nil)
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

    // MARK: - Reroute gating

    private var pendingRerouteBinding: Binding<PendingReroute?> {
        Binding(
            get: { pendingReroute.map { PendingReroute(server: $0.server, ip: $0.ip) } },
            set: { if $0 == nil { pendingReroute = nil } }
        )
    }

    private struct PendingReroute: Identifiable {
        let server: RobotServer
        let ip: String
        var id: String { ip }
    }

    /// Chaining one sheet into another in the same tick races SwiftUI's
    /// dismissal animation — a short hop lets the outgoing sheet finish
    /// dismissing first, mirroring `DedicatedServerDetailView`.
    private func presentAfterDismiss(_ present: @escaping () -> Void) {
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            present()
        }
    }

    /// Routing changes are outage-grade: biometrics are ALWAYS required
    /// here, unlike every other destructive action in Dedicated (which only
    /// gates when the user's "require biometrics for destructive actions"
    /// setting is on).
    private func confirmReroute(to targetIP: String) {
        guard let viewModel else { return }
        gateError = nil
        isAuthenticatingReroute = true
        Task {
            let reason = "Confirm rerouting \(route.ip) to \(targetIP)"
            let approved = await container.biometricGate.authenticate(reason: reason)
            isAuthenticatingReroute = false
            if approved {
                pendingReroute = nil
                viewModel.switchRouting(to: targetIP)
            } else {
                gateError = container.biometricGate.lastErrorMessage ?? "Authentication failed. Try again."
            }
        }
    }

    private func confirmRemoveRouting() {
        guard let viewModel else { return }
        gateError = nil
        isAuthenticatingReroute = true
        Task {
            let reason = "Confirm removing routing for \(route.ip)"
            let approved = await container.biometricGate.authenticate(reason: reason)
            isAuthenticatingReroute = false
            if approved {
                viewModel.removeRouting()
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
        FailoverDetailView(route: FailoverRoute(accountID: UUID(), ip: NetworkPreviewFixtures.failoverIP.ip))
            .environment(AppContainer.makeDefault())
    }
    .preferredColorScheme(.dark)
}
