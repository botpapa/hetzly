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
    @State private var isAddProjectPresented = false
    @State private var updateTokenProject: ProjectRecord?

    /// Which projects' sections are collapsed in "All" mode. Empty by
    /// default (every section starts expanded); intentionally not
    /// persisted — a fresh launch always shows everything.
    @State private var collapsedProjectIDs: Set<UUID> = []

    /// Dashboard-wide project scope: `nil` means "All". Persisted as a raw
    /// UUID string (`AppStorage` has no native `UUID?` support) so the scope
    /// survives relaunch; an empty string round-trips to `nil`.
    @AppStorage("dashboard.selectedProject") private var selectedProjectIDRaw = ""

    private var selectedProjectID: UUID? {
        UUID(uuidString: selectedProjectIDRaw)
    }

    private var selectedProjectIDBinding: Binding<UUID?> {
        Binding(
            get: { selectedProjectID },
            set: { selectedProjectIDRaw = $0?.uuidString ?? "" }
        )
    }

    /// `viewModel.projectSections`, scoped to the selected project — the
    /// other projects' sections are skipped entirely rather than shown
    /// collapsed, per the filter contract.
    private var visibleProjectSections: [DashboardViewModel.ProjectSection] {
        guard let selectedProjectID else { return viewModel.projectSections }
        return viewModel.projectSections.filter { $0.projectID == selectedProjectID }
    }

    private var visibleAttention: [ServerListItem] {
        guard let selectedProjectID else { return viewModel.attention }
        return viewModel.attention.filter { $0.projectID == selectedProjectID }
    }

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
                        ProjectFilterBar(
                            projects: container.projectsStore.projects,
                            selection: selectedProjectIDBinding,
                            onAddProject: { isAddProjectPresented = true }
                        )

                        freshnessBanner

                        BurnCardView(
                            monthToDate: scopedBurn.monthToDate,
                            projected: scopedBurn.projected,
                            currency: viewModel.currency,
                            idleMascotState: idleMascotState
                        )

                        if !visibleAttention.isEmpty {
                            AttentionSectionView(
                                items: visibleAttention,
                                cpuSamples: viewModel.cpuSparklines,
                                mascotEnabled: container.settings.mascotEnabled
                            )
                        }

                        ForEach(visibleProjectSections) { section in
                            projectSection(section)
                        }

                        if selectedProjectID == nil, !viewModel.dedicatedServers.isEmpty || viewModel.dedicatedError != nil {
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
            .navigationDestination(for: ProjectRoute.self) { route in
                ProjectDetailView(route: route)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // Always a menu (never a direct-tap shortcut): "Add
                    // Project" starts the sync-a-new-project flow, "Create
                    // Server" either jumps straight into the wizard (exactly
                    // one project) or opens a nested project-picker submenu
                    // (more than one) — disabled with no projects at all.
                    Menu {
                        Button {
                            isAddProjectPresented = true
                        } label: {
                            Label("Add Project", systemImage: "folder.badge.plus")
                        }

                        createServerMenuEntry
                    } label: {
                        // "New", not "Add" — `HetzlyUITestCase.element(labeled:)`
                        // matches substrings case-insensitively, and
                        // `ProjectFilterBar`'s "+" chip is already
                        // accessibility-labeled "Add project"; a same-prefix
                        // label here would make that lookup ambiguous.
                        Label("New", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $createServerTarget) { target in
                CreateServerFlow(projectID: target.id) { _ in
                    Task { await viewModel.refresh(container: container) }
                }
            }
            .sheet(item: $updateTokenProject) { project in
                UpdateTokenSheet(project: project)
                    .onDisappear {
                        Task { await viewModel.refresh(container: container) }
                    }
            }
            .sheet(isPresented: $isAddProjectPresented) {
                AddProjectSheet()
            }
        }
        .task {
            await viewModel.load(container: container)
            resetIdleTimer()
        }
    }

    /// The burn card's figures, scoped to `selectedProjectID` ("All" shows
    /// the combined totals). Widgets still get the unfiltered combined
    /// totals via `DashboardViewModel.writeWidgetSnapshot()` — this scoping
    /// is purely a display concern.
    private var scopedBurn: (monthToDate: Decimal?, projected: Decimal?) {
        viewModel.burn(for: selectedProjectID)
    }

    /// The toolbar "+" menu's "Create Server" entry: zero projects disables
    /// it outright, exactly one jumps straight into the wizard for it, and
    /// more than one exposes a nested submenu of projects (the accessible
    /// label stays "Create Server" either way, so UI tests can keep finding
    /// it by that text once the parent menu is open).
    @ViewBuilder
    private var createServerMenuEntry: some View {
        let projects = container.projectsStore.projects
        if projects.isEmpty {
            Button {
            } label: {
                Label("Create Server", systemImage: "server.rack")
            }
            .disabled(true)
        } else if projects.count == 1, let only = projects.first {
            Button {
                createServerTarget = CreateServerTarget(id: only.id)
            } label: {
                Label("Create Server", systemImage: "server.rack")
            }
        } else {
            Menu {
                ForEach(projects) { project in
                    Button(project.name) {
                        createServerTarget = CreateServerTarget(id: project.id)
                    }
                }
            } label: {
                Label("Create Server", systemImage: "server.rack")
            }
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

    /// Collapse is an "All" mode affordance only — with a single project
    /// selected there's nothing else on screen to collapse away from, so
    /// the section always renders expanded and the toggle is hidden.
    private func isCollapsed(_ section: DashboardViewModel.ProjectSection) -> Bool {
        selectedProjectID == nil && collapsedProjectIDs.contains(section.projectID)
    }

    @ViewBuilder
    private func projectSection(_ section: DashboardViewModel.ProjectSection) -> some View {
        let collapsed = isCollapsed(section)

        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            HStack(spacing: Spacing.unit * 2) {
                NavigationLink(value: ProjectRoute(projectID: section.projectID)) {
                    HStack(spacing: Spacing.unit) {
                        SectionLabel(section.projectName)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(HetzlyColors.textTertiary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if section.isStale {
                    GlassChip("Stale", systemImage: "clock.arrow.circlepath")
                }

                if collapsed {
                    GlassChip(collapsedSummary(for: section))
                }

                if selectedProjectID == nil {
                    Button {
                        toggleCollapsed(section.projectID)
                    } label: {
                        Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(HetzlyColors.textTertiary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(collapsed ? "Expand \(section.projectName)" : "Collapse \(section.projectName)")
                }
            }

            if !collapsed {
                if let errorMessage = section.errorMessage {
                    GlassCard {
                        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                            HStack(spacing: Spacing.unit * 2) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(HetzlyColors.statusError)
                                Text(errorMessage)
                                    .bodySecondary()
                            }
                            // Auth failures are recoverable in place: a
                            // rotated/revoked key just needs replacing.
                            if isAuthError(errorMessage),
                               let project = container.projectsStore.projects.first(
                                where: { $0.id == section.projectID }
                               ) {
                                Button("Update token…") {
                                    updateTokenProject = project
                                }
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(HetzlyColors.accent)
                            }
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
        .animation(.snappy, value: collapsed)
    }

    /// A section error is auth-related (revoked/rotated key) when it carries
    /// the `HetznerAPIError.unauthorized` user message — matched on the
    /// stable "token was rejected" phrase since `ProjectSection` transports
    /// only the rendered string, not the typed error.
    private func isAuthError(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("token was rejected")
    }

    /// "N servers · M running" summary chip shown in place of the full
    /// server list when a section is collapsed.
    private func collapsedSummary(for section: DashboardViewModel.ProjectSection) -> String {
        let total = section.servers.count
        let running = section.servers.filter { $0.status == .running }.count
        return "\(total) server\(total == 1 ? "" : "s") · \(running) running"
    }

    private func toggleCollapsed(_ projectID: UUID) {
        withAnimation(.snappy) {
            if collapsedProjectIDs.contains(projectID) {
                collapsedProjectIDs.remove(projectID)
            } else {
                collapsedProjectIDs.insert(projectID)
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

#Preview("Multi-project") {
    // Note: `ProjectFilterBar`'s chips read live `ProjectRecord`s from
    // `AppContainer.projectsStore` (per the module contract, not from the
    // view model), so this preview exercises section collapse and the
    // per-project burn card scoping via `previewMultiProject`'s three
    // `ProjectSection`s + `perProjectBurn`; the filter bar itself renders
    // whatever projects (if any) exist in `AppContainer.makeDefault()`'s
    // on-disk store, matching the same pre-existing constraint the
    // create-server toolbar menu already has.
    DashboardView(previewViewModel: .previewMultiProject)
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}

#Preview("Appearance: Light") {
    DashboardView(previewViewModel: .previewHealthy)
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.light)
}
