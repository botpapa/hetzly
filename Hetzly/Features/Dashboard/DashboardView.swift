import SwiftUI

/// The app's home screen: cost burn aggregated across every project,
/// servers needing attention, and a per-project server list. Reads
/// `AppContainer` from the environment per the module contract.
struct DashboardView: View {
    @Environment(AppContainer.self) private var container
    @State private var viewModel: DashboardViewModel
    @State private var idleTimerTask: Task<Void, Never>?
    @State private var mascotIsAsleep = false
    /// Sheet-item wrapper: the project a new server should be created in.
    private struct CreateServerTarget: Identifiable {
        let id: UUID
    }

    @State private var createServerTarget: CreateServerTarget?

    init() {
        _viewModel = State(initialValue: DashboardViewModel())
    }

    /// Preview/test-only entry point: injects a pre-populated view model so
    /// previews never touch the network or a real `AppContainer` load path.
    init(previewViewModel: DashboardViewModel) {
        _viewModel = State(initialValue: previewViewModel)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                CanvasBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.unit * 6) {
                        freshnessBanner

                        BurnCardView(
                            monthToDate: viewModel.monthToDate,
                            projected: viewModel.projected,
                            currency: viewModel.currency,
                            idleMascotState: idleMascotState
                        )

                        if !viewModel.attention.isEmpty {
                            AttentionSectionView(
                                items: viewModel.attention,
                                cpuSamples: viewModel.cpuSparklines,
                                mascotEnabled: container.settings.mascotEnabled
                            )
                        }

                        ForEach(viewModel.projectSections) { section in
                            projectSection(section)
                        }

                        if !viewModel.dedicatedServers.isEmpty || viewModel.dedicatedError != nil {
                            DedicatedSectionView(
                                servers: viewModel.dedicatedServers,
                                errorMessage: viewModel.dedicatedError
                            )
                        }
                    }
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.vertical, Spacing.screenMargin)
                }
                .refreshable {
                    resetIdleTimer()
                    await viewModel.refresh(container: container)
                }
                .simultaneousGesture(TapGesture().onEnded { resetIdleTimer() })

                // Max one mascot instance on screen at a time: when the
                // "Attention" section is showing its own alarm mascot, that
                // one wins and the refresh-run mascot sits out this refresh
                // rather than doubling up.
                if viewModel.isRefreshing, container.settings.mascotEnabled, viewModel.attention.isEmpty {
                    refreshingMascotOverlay
                }
            }
            .navigationTitle("Dashboard")
            .navigationDestination(for: ServerRoute.self) { route in
                ServerDetailView(route: route)
            }
            .navigationDestination(for: RobotServerRoute.self) { route in
                DedicatedServerDetailView(route: route)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // Single project: tap goes straight into the wizard.
                    // Multiple: tap opens a project picker menu. (A Menu with
                    // primaryAction won't do here — its tap fires the action
                    // and only a long-press reveals the menu, which made the
                    // button a no-op with >1 projects.)
                    if container.projectsStore.projects.count == 1,
                       let only = container.projectsStore.projects.first {
                        Button {
                            createServerTarget = CreateServerTarget(id: only.id)
                        } label: {
                            Label("Create Server", systemImage: "plus")
                        }
                    } else {
                        Menu {
                            ForEach(container.projectsStore.projects) { project in
                                Button(project.name) {
                                    createServerTarget = CreateServerTarget(id: project.id)
                                }
                            }
                        } label: {
                            Label("Create Server", systemImage: "plus")
                        }
                    }
                }
            }
            .sheet(item: $createServerTarget) { target in
                CreateServerFlow(projectID: target.id) { _ in
                    Task { await viewModel.refresh(container: container) }
                }
            }
        }
        .task {
            await viewModel.load(container: container)
            resetIdleTimer()
        }
    }

    // MARK: - Freshness banner

    @ViewBuilder
    private var freshnessBanner: some View {
        switch viewModel.freshnessBanner {
        case .none:
            EmptyView()
        case .refreshingCache:
            GlassChip("Showing cached data — refreshing…", systemImage: "arrow.triangle.2.circlepath")
        case .offlineCache:
            GlassChip("Offline — showing cached data", systemImage: "wifi.slash")
        }
    }

    // MARK: - Refresh mascot

    /// The pull-to-refresh signature moment: Hetzi runs across the top while
    /// a refresh is in flight. Note (M1): the system pull-to-refresh spinner
    /// still renders above the scroll content per platform behavior — this
    /// mascot is an additional, intentional layer on top of it, not a
    /// replacement for it.
    private var refreshingMascotOverlay: some View {
        VStack {
            HStack {
                Spacer()
                MascotView(state: .run, scale: 2)
                    .padding(.trailing, Spacing.screenMargin)
                    .padding(.top, Spacing.unit * 2)
            }
            Spacer()
        }
        .allowsHitTesting(false)
    }

    // MARK: - Idle mascot

    /// Perched on the burn card's top-trailing edge only when everything is
    /// healthy (no attention items, no per-project errors), not refreshing,
    /// and the mascot is enabled in settings. Falls asleep after 30s of no
    /// interaction; any tap or pull-to-refresh resets the timer.
    private var idleMascotState: MascotState? {
        guard container.settings.mascotEnabled, viewModel.isHealthy, !viewModel.isRefreshing else { return nil }
        return mascotIsAsleep ? .sleep : .idle
    }

    private func resetIdleTimer() {
        mascotIsAsleep = false
        idleTimerTask?.cancel()
        idleTimerTask = Task {
            try? await Task.sleep(for: .seconds(30))
            if !Task.isCancelled {
                mascotIsAsleep = true
            }
        }
    }

    // MARK: - Per-project section

    @ViewBuilder
    private func projectSection(_ section: DashboardViewModel.ProjectSection) -> some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            HStack {
                SectionLabel(section.projectName)
                Spacer()
                if section.isStale {
                    GlassChip("Stale", systemImage: "clock.arrow.circlepath")
                }
            }

            if let errorMessage = section.errorMessage {
                GlassCard {
                    HStack(spacing: Spacing.unit * 2) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(HetzlyColors.statusError)
                        Text(errorMessage)
                            .bodySecondary()
                    }
                }
            }

            if section.servers.isEmpty {
                if section.errorMessage == nil {
                    GlassCard {
                        Text("No servers in this project")
                            .bodySecondary()
                    }
                }
            } else {
                VStack(spacing: Spacing.unit * 2) {
                    ForEach(section.servers) { item in
                        NavigationLink(value: ServerRoute(projectID: item.projectID, serverID: item.serverID)) {
                            ServerRowView(item: item, cpuSamples: viewModel.cpuSparklines[item.id])
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

#Preview("Healthy") {
    DashboardView(previewViewModel: .previewHealthy)
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}

#Preview("Attention") {
    DashboardView(previewViewModel: .previewAttention)
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}

#Preview("Stale / offline") {
    DashboardView(previewViewModel: .previewStaleOffline)
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}

#Preview("Empty project") {
    DashboardView(previewViewModel: .previewEmptyProject)
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}
