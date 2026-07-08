import SwiftUI

/// The Costs tab: month-to-date and projected spend across every project,
/// computed 100% on-device from live inventory × Hetzner pricing (no
/// third-party service ever sees a token or a number). Binding entry point
/// per the M2 Wave B contract: `CostsView()` reading `AppContainer` from
/// the environment, owning its own `NavigationStack`.
struct CostsView: View {
    @Environment(AppContainer.self) private var container
    @State private var viewModel: CostsViewModel
    @State private var manualStore = ManualCostStore()
    @State private var dedicatedPriceStore = DedicatedPriceStore()
    @State private var isPresentingAddManual = false
    @State private var editingManualEntry: ManualCostEntry?
    @State private var settingPriceForServer: CostsViewModel.DedicatedServerRow?
    @State private var shareImage: Image?
    @State private var isPresentingAddProject = false

    /// The project Costs is currently scoped to; `nil` = "All". Backed by
    /// `@AppStorage` (stored as a `String` since `AppStorage` has no native
    /// `UUID?` support) so the scope survives relaunches, matching
    /// `ResourcesHubView`'s "resources.selectedProject" persistence.
    @AppStorage("costs.selectedProject") private var selectedProjectIDStorage = ""

    private var selectedProjectID: Binding<UUID?> {
        Binding(
            get: { UUID(uuidString: selectedProjectIDStorage) },
            set: { selectedProjectIDStorage = $0?.uuidString ?? "" }
        )
    }

    init() {
        _viewModel = State(initialValue: CostsViewModel())
    }

    /// Preview/test-only entry point: injects a pre-populated view model so
    /// previews never touch the network.
    init(previewViewModel: CostsViewModel) {
        _viewModel = State(initialValue: previewViewModel)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.unit * 6) {
                        ProjectFilterBar(
                            projects: container.projectsStore.projects,
                            selection: selectedProjectID,
                            onAddProject: { isPresentingAddProject = true }
                        )

                        let hero = viewModel.heroSummary(forProjectID: scopedProjectID)
                        CostsHeroCard(
                            monthToDate: hero.monthToDate,
                            projected: hero.projected,
                            currency: viewModel.currency,
                            monthElapsedFraction: viewModel.monthElapsedFraction
                        )

                        if viewModel.isEmpty && !viewModel.isLoading {
                            emptyState
                        } else {
                            if visibleKindShares.count > 1 {
                                GlassCard {
                                    VStack(alignment: .leading, spacing: Spacing.unit * 4) {
                                        SectionLabel("Spend by kind")
                                        CostKindDonutChart(
                                            shares: visibleKindShares,
                                            currency: viewModel.currency
                                        )
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }

                            ForEach(visibleProjectSections) { section in
                                CostProjectSectionView(section: section, currency: viewModel.currency)
                            }
                        }

                        // Dedicated servers and manual entries aren't tied to
                        // any Cloud project, so they only make sense in the
                        // combined "All" view — scoping to one project would
                        // otherwise show costs that don't belong to it.
                        if scopedProjectID == nil {
                            DedicatedCostSection(
                                dedicatedServers: viewModel.dedicatedServers,
                                dedicatedErrorMessage: viewModel.dedicatedErrorMessage,
                                manualEntries: manualStore.entries,
                                currency: viewModel.currency,
                                onSetPrice: { settingPriceForServer = $0 },
                                onAddManual: { isPresentingAddManual = true },
                                onEditManual: { editingManualEntry = $0 },
                                onDeleteManual: { removeManualEntry($0) }
                            )
                        }
                    }
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.vertical, Spacing.screenMargin)
                    .animation(.smooth, value: manualStore.entries)
                    .animation(.smooth, value: dedicatedPriceStore.entries)
                    .animation(.snappy, value: scopedProjectID)
                }
                .refreshable {
                    await viewModel.refresh(container: container, manualEntries: manualStore.entries, dedicatedPrices: dedicatedPriceStore.entries)
                }
            }
            .navigationTitle("Costs")
            .navigationDestination(for: ProjectRoute.self) { route in
                ProjectDetailView(route: route)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        InvoicesView()
                    } label: {
                        Label("Invoices", systemImage: "doc.text")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let shareImage {
                        ShareLink(
                            item: shareImage,
                            preview: SharePreview("Hetzly — \(monthTitle) costs", image: shareImage)
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share Costs Summary")
                        .tint(HetzlyColors.accent)
                    }
                }
            }
        }
        .task {
            await viewModel.load(container: container, manualEntries: manualStore.entries, dedicatedPrices: dedicatedPriceStore.entries)
        }
        .task(id: shareRenderKey) {
            await renderShareCard()
        }
        .onChange(of: container.projectsStore.projects.map(\.id)) { _, currentIDs in
            // The scoped project may have been removed (Settings) while
            // Costs was showing it — fall back to "All" rather than showing
            // an empty scope with no way out.
            if let scopedProjectID, !currentIDs.contains(scopedProjectID) {
                selectedProjectIDStorage = ""
            }
        }
        .onChange(of: manualStore.entries) {
            // Manual entries feed the combined summary; recompute without a
            // full network refresh isn't possible through the public
            // surface, so refresh (per-project pricing is memoized, so this
            // is cheap in practice).
            Task {
                await viewModel.refresh(container: container, manualEntries: manualStore.entries, dedicatedPrices: dedicatedPriceStore.entries)
            }
        }
        .onChange(of: dedicatedPriceStore.entries) {
            // Same rationale as manual entries above — and `RobotClient`'s
            // own 5-minute response cache means re-fetching Robot servers
            // right after a local price edit doesn't cost a real request.
            Task {
                await viewModel.refresh(container: container, manualEntries: manualStore.entries, dedicatedPrices: dedicatedPriceStore.entries)
            }
        }
        .sheet(isPresented: $isPresentingAddManual) {
            ManualCostSheet(store: manualStore, currency: viewModel.currency)
        }
        .sheet(item: $editingManualEntry) { entry in
            ManualCostSheet(store: manualStore, currency: viewModel.currency, editing: entry)
        }
        .sheet(item: $settingPriceForServer) { server in
            DedicatedPriceSheet(
                store: dedicatedPriceStore,
                currency: viewModel.currency,
                serverNumber: server.serverNumber,
                serverName: server.name,
                existing: dedicatedPriceStore.price(for: server.serverNumber)
            )
        }
        .sheet(isPresented: $isPresentingAddProject) {
            AddProjectSheet()
        }
    }

    // MARK: - Project scope

    private var scopedProjectID: UUID? {
        selectedProjectID.wrappedValue
    }

    /// `viewModel.projectSections` narrowed to the scoped project, or every
    /// section when scope is "All".
    private var visibleProjectSections: [CostsViewModel.ProjectSection] {
        guard let scopedProjectID else { return viewModel.projectSections }
        return viewModel.projectSections.filter { $0.projectID == scopedProjectID }
    }

    /// The donut's slices: the scoped project's own kind breakdown, or the
    /// combined breakdown across every project when scope is "All".
    private var visibleKindShares: [CostsViewModel.KindShare] {
        guard scopedProjectID != nil else { return viewModel.kindShares }
        return visibleProjectSections.first?.kindShares ?? []
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: Spacing.unit * 5) {
            if container.settings.mascotEnabled {
                MascotView(state: .idle, scale: 4)
            }
            VStack(spacing: Spacing.unit * 2) {
                Text("Nothing to count yet.")
                    .bodyPrimary()
                Text("Servers, volumes, and IPs you create will show up here with live cost math.")
                    .bodySecondary()
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.unit * 10)
    }

    // MARK: - Manual entries

    private func removeManualEntry(_ entry: ManualCostEntry) {
        withAnimation(.smooth) {
            manualStore.remove(entry)
        }
    }

    // MARK: - Share card

    private var monthTitle: String {
        Date().formatted(.dateTime.month(.wide).year())
    }

    /// Re-render whenever the numbers the card shows change.
    private var shareRenderKey: String {
        let mtd = viewModel.combinedMonthToDate.map { "\($0)" } ?? "-"
        let projected = viewModel.combinedProjected.map { "\($0)" } ?? "-"
        let projects = viewModel.projectSections.map { "\($0.projectName)=\($0.projectedTotal)" }.joined(separator: ",")
        return "\(mtd)|\(projected)|\(viewModel.currency)|\(projects)"
    }

    private func renderShareCard() async {
        guard let monthToDate = viewModel.combinedMonthToDate,
              let projected = viewModel.combinedProjected
        else {
            shareImage = nil
            return
        }

        let projectTotals = viewModel.projectSections
            .filter { $0.projectedTotal > 0 }
            .map { (name: $0.projectName, projected: $0.projectedTotal) }

        shareImage = await CostShareCardRenderer.render(
            monthToDate: monthToDate,
            projected: projected,
            currency: viewModel.currency,
            monthTitle: monthTitle,
            projectTotals: projectTotals
        )
    }
}

#Preview("Rich multi-project") {
    CostsView(previewViewModel: CostsPreviewFixtures.richViewModel)
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}

#Preview("Empty") {
    CostsView(previewViewModel: CostsPreviewFixtures.emptyViewModel)
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}
