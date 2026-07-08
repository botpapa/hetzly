import HetznerKit
import SwiftUI
import UIKit

/// The app's home screen: cost burn aggregated across every project,
/// servers needing attention, and a per-project server list. Reads
/// `AppContainer` from the environment per the module contract.
struct DashboardView: View {
    @Environment(AppContainer.self) private var container
    /// Deep-link routing (`hetzly://server/…`, `hetzly://project/…`,
    /// `hetzly://dashboard`) — see `AppRouter.pendingRoute`. Dashboard is
    /// the tab that owns both `.navigationDestination(for: ServerRoute.self)`
    /// and `.navigationDestination(for: ProjectRoute.self)`, so it's the one
    /// that consumes a pending route once it arrives.
    @Environment(AppRouter.self) private var router
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

    // MARK: - Server search

    /// `.searchable`-bound query. Deliberately NOT project-scoped: search
    /// overrides `selectedProjectID` entirely rather than filtering within
    /// it (see `searchResults`) — typing into search means "I don't know
    /// which project this server is in," so honoring the current scope
    /// filter here would actively work against the reason someone reaches
    /// for search in the first place.
    @State private var searchText = ""

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Flat, cross-project matches for `searchText` — name (substring,
    /// case-insensitive) or public IPv4 (substring). Filters the sections
    /// already held in memory; no network call of its own.
    private var searchResults: [ServerListItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        return viewModel.projectSections.flatMap(\.servers).filter { item in
            item.name.lowercased().contains(query) || (item.publicIPv4?.lowercased().contains(query) ?? false)
        }
    }

    private func projectName(for projectID: UUID) -> String {
        viewModel.projectSections.first(where: { $0.projectID == projectID })?.projectName ?? ""
    }

    // MARK: - Row quick actions

    /// A contextual power action awaiting confirmation from a dashboard
    /// row's `.contextMenu`, driving the compact `confirmationDialog` below.
    private struct PendingRowAction: Identifiable {
        let action: PowerAction
        let item: ServerListItem
        var id: String { item.id + action.rawValue }
    }

    @State private var pendingRowAction: PendingRowAction?
    @State private var rowActionAuthError: String?
    @State private var copyHapticTrigger = false

    /// Explicit navigation path so the row context menu's "View Details"
    /// item can push programmatically. A `NavigationLink` nested inside a
    /// `.contextMenu` doesn't reliably present the menu (and reads oddly in
    /// the menu's flat button list), so "View Details" is a plain `Button`
    /// that appends onto this path instead — the row's own tap-to-navigate
    /// keeps using value-based links, which drive the same bound path.
    @State private var navigationPath = NavigationPath()

    init() {
        _viewModel = State(initialValue: DashboardViewModel())
    }

    /// Preview/test-only entry point: injects a pre-populated view model so
    /// previews never touch the network or a real `AppContainer` load path.
    init(previewViewModel: DashboardViewModel) {
        _viewModel = State(initialValue: previewViewModel)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .top) {
                CanvasBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.unit * 6) {
                        ProjectFilterBar(
                            projects: container.projectsStore.projects,
                            selection: selectedProjectIDBinding,
                            onAddProject: { isAddProjectPresented = true }
                        )

                        if isSearching {
                            searchResultsSection
                        } else {
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

                            if selectedProjectID == nil {
                                if !viewModel.dedicatedServers.isEmpty || viewModel.dedicatedError != nil {
                                    DedicatedSectionView(
                                        servers: viewModel.dedicatedServers,
                                        errorMessage: viewModel.dedicatedError,
                                        isAuthError: viewModel.dedicatedIsAuthError
                                    )
                                }
                            } else if !viewModel.dedicatedServers.isEmpty {
                                // A project scope is selected but Dedicated
                                // (Robot) servers aren't project-scoped at
                                // all — rather than silently omitting them
                                // (which reads as "no dedicated servers
                                // exist"), say where they actually are.
                                GlassChip("Dedicated servers are shown under All", systemImage: "server.rack")
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.vertical, Spacing.screenMargin)
                }
                .refreshable {
                    resetIdleTimer()
                    await viewModel.refresh(container: container)
                }
                // No whole-surface tap/gesture recognizer here (there used to
                // be a `.simultaneousGesture(TapGesture()...)` for idle-timer
                // resets) — even a `simultaneous` gesture recognizer sitting
                // over the entire scroll content competes with child
                // `NavigationLink`/`Button` hit-testing and was intermittently
                // swallowing row taps. Scroll activity resets the idle timer
                // instead, via `onScrollGeometryChange`; `.refreshable` above
                // and the `.task` load below cover pull-to-refresh and
                // fresh-launch/return-from-navigation resets.
                .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, _ in
                    resetIdleTimer()
                }
                .sensoryFeedback(.impact(weight: .light), trigger: copyHapticTrigger)

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
            .confirmationDialog(
                rowActionDialogTitle,
                isPresented: rowActionDialogPresented,
                titleVisibility: .visible
            ) {
                if let pendingRowAction {
                    Button(
                        pendingRowAction.action.confirmButtonTitle,
                        role: pendingRowAction.action.isDestructive ? .destructive : nil
                    ) {
                        confirmRowAction(pendingRowAction)
                    }
                    Button("Cancel", role: .cancel) {
                        self.pendingRowAction = nil
                    }
                }
            } message: {
                if let pendingRowAction {
                    Text(pendingRowAction.action.confirmSubtitle)
                }
            }
            .alert(
                "Authentication Failed",
                isPresented: Binding(
                    get: { rowActionAuthError != nil },
                    set: { if !$0 { rowActionAuthError = nil } }
                ),
                presenting: rowActionAuthError
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .searchable(text: $searchText, prompt: "Search servers")
        }
        .task {
            resetScopeIfProjectMissing()
            await viewModel.load(container: container)
            resetIdleTimer()
        }
        .onChange(of: container.projectsStore.projects.map(\.id)) { _, _ in
            // The scoped project may have been removed (Settings) — or, in
            // UI-test seeding, the demo project gets a fresh UUID each launch
            // while the persisted scope survives. Either way, a scope that
            // matches no existing project would render a blank dashboard, so
            // fall back to "All".
            resetScopeIfProjectMissing()
        }
        // Consumes a deep link's pending route once `AppRouter` has already
        // switched to this tab. Resets to a fresh path first (a `.server`/
        // `.project`/`.dashboard` deep link always means "go here", not
        // "push onto whatever was already on screen") and clears
        // `pendingRoute` so this doesn't refire on the next unrelated
        // observable change on `router`.
        //
        // `initial: true` is load-bearing: a launch-time deep link (widget
        // tap / Shortcut) sets `pendingRoute` from `HetzlyApp`'s `.task`,
        // which can land before this `.onChange` starts observing — a plain
        // `onChange` never fires for a value that's already set when the
        // observer attaches, so the route would be silently dropped. Firing
        // once on appear with the current value closes that race (and is a
        // harmless no-op via the `guard` when nothing is pending).
        .onChange(of: router.pendingRoute, initial: true) { _, newValue in
            guard let newValue else { return }
            switch newValue {
            case .server(let route):
                navigationPath = NavigationPath()
                navigationPath.append(route)
            case .project(let route):
                navigationPath = NavigationPath()
                navigationPath.append(route)
            case .dashboard:
                navigationPath = NavigationPath()
            case .costs:
                break
            }
            router.pendingRoute = nil
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

    /// Clears the persisted project scope back to "All" when it points at a
    /// project that no longer exists, so the dashboard never renders blank.
    private func resetScopeIfProjectMissing() {
        guard let selectedProjectID else { return }
        if !container.projectsStore.projects.contains(where: { $0.id == selectedProjectID }) {
            selectedProjectIDRaw = ""
        }
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
                            if section.isAuthError,
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
                            serverRow(item)
                        }
                    }
                }
            }
        }
        .animation(.snappy, value: collapsed)
    }

    /// A single dashboard row: tapping navigates into Server Detail, plus the
    /// row quick-actions `.contextMenu` (Copy IPv4, contextual power actions,
    /// View Details) and its unobtrusive in-flight spinner. Shared by both
    /// per-project sections and the flat search-results list below.
    ///
    /// Deliberately a plain view with a separate `.onTapGesture` (navigating
    /// by appending to `navigationPath`) rather than a `NavigationLink` or
    /// `Button`: both of those win the press outright and fire their
    /// navigation on release before the long-press context-menu recognizer
    /// ever engages, so the menu never opens (a real interaction bug, caught
    /// by `test_dashboard_rowContextMenu_showsQuickActions`). With an
    /// independent tap gesture the short-tap and the `.contextMenu`
    /// long-press coexist — SwiftUI routes each to the right recognizer.
    private func serverRow(_ item: ServerListItem, projectCaption: String? = nil) -> some View {
        ServerRowView(item: item, cpuSamples: viewModel.cpuSparklines[item.id], projectName: projectCaption)
            .overlay(alignment: .leading) {
                if viewModel.rowActionInFlight.contains(item.id) {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, Spacing.unit)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                navigationPath.append(ServerRoute(projectID: item.projectID, serverID: item.serverID))
            }
            .contextMenu {
                rowContextMenu(for: item)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
    }

    // MARK: - Row quick actions (context menu + confirm + fire)

    @ViewBuilder
    private func rowContextMenu(for item: ServerListItem) -> some View {
        Button {
            copyIPv4(item)
        } label: {
            Label("Copy IPv4", systemImage: "doc.on.doc")
        }
        .disabled(item.publicIPv4 == nil)

        Button {
            navigationPath.append(ServerRoute(projectID: item.projectID, serverID: item.serverID))
        } label: {
            Label("View Details", systemImage: "info.circle")
        }

        switch item.status {
        case .running:
            Divider()
            Button {
                requestRowAction(.reboot, item: item)
            } label: {
                Label("Reboot", systemImage: "arrow.clockwise")
            }
            Button {
                requestRowAction(.shutdown, item: item)
            } label: {
                Label("Shut Down", systemImage: "moon")
            }
        case .off:
            Divider()
            Button {
                requestRowAction(.powerOn, item: item)
            } label: {
                Label("Power On", systemImage: "power")
            }
        default:
            EmptyView()
        }
    }

    /// Copies the row's public IPv4 to the pasteboard and fires the same
    /// light-impact haptic `ServerHeroCard`'s tap-to-copy uses. A no-op when
    /// the item has no known IPv4 (the menu item is disabled in that case
    /// too, so this is just defense in depth).
    private func copyIPv4(_ item: ServerListItem) {
        guard let ip = item.publicIPv4 else { return }
        UIPasteboard.general.string = ip
        copyHapticTrigger.toggle()
    }

    /// Stages a contextual power action for confirmation — the
    /// `confirmationDialog` attached to the `NavigationStack` reads
    /// `pendingRowAction` back out.
    private func requestRowAction(_ action: PowerAction, item: ServerListItem) {
        pendingRowAction = PendingRowAction(action: action, item: item)
    }

    /// Mirrors `ServerDetailView.confirm(_:)`'s gating: destructive actions
    /// go through `container.biometricGate` first (when the user has opted
    /// into `requireBiometricsForDestructive`), everything else fires
    /// immediately. None of the three actions this menu offers
    /// (reboot/shutdown/power-on) are actually `isDestructive` today, so the
    /// gate is a no-op in practice — kept here so that stays true by
    /// contract rather than by accident, and so a future destructive row
    /// action gets the gate for free.
    private func confirmRowAction(_ pending: PendingRowAction) {
        guard pending.action.isDestructive, container.settings.requireBiometricsForDestructive else {
            fireRowAction(pending)
            return
        }
        Task {
            let reason = "Confirm \(pending.action.title.lowercased()) for \(pending.item.name)"
            let approved = await container.biometricGate.authenticate(reason: reason)
            if approved {
                fireRowAction(pending)
            } else {
                rowActionAuthError = container.biometricGate.lastErrorMessage ?? "Authentication failed. Try again."
            }
        }
    }

    private func fireRowAction(_ pending: PendingRowAction) {
        pendingRowAction = nil
        Task { await viewModel.performRowAction(pending.action, item: pending.item, container: container) }
    }

    private var rowActionDialogTitle: String {
        guard let pendingRowAction else { return "" }
        return "\(pendingRowAction.action.title) \(pendingRowAction.item.name)?"
    }

    private var rowActionDialogPresented: Binding<Bool> {
        Binding(
            get: { pendingRowAction != nil },
            set: { if !$0 { pendingRowAction = nil } }
        )
    }

    // MARK: - Search results

    @ViewBuilder
    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            SectionLabel("Results")

            if searchResults.isEmpty {
                GlassCard {
                    Text("No servers match \u{201C}\(searchText)\u{201D}")
                        .bodySecondary()
                }
            } else {
                VStack(spacing: Spacing.unit * 2) {
                    ForEach(searchResults) { item in
                        serverRow(item, projectCaption: projectName(for: item.projectID))
                    }
                }
            }
        }
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
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}

#Preview("Attention") {
    DashboardView(previewViewModel: .previewAttention)
        .environment(AppContainer.makeDefault())
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}

#Preview("Stale / offline") {
    DashboardView(previewViewModel: .previewStaleOffline)
        .environment(AppContainer.makeDefault())
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}

#Preview("Empty project") {
    DashboardView(previewViewModel: .previewEmptyProject)
        .environment(AppContainer.makeDefault())
        .environment(AppRouter())
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
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}

#Preview("Appearance: Light") {
    DashboardView(previewViewModel: .previewHealthy)
        .environment(AppContainer.makeDefault())
        .environment(AppRouter())
        .preferredColorScheme(.light)
}
