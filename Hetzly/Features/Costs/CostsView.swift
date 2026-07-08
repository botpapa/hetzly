import SwiftUI

/// Identifies the Cloud server `CloudServerPriceSheet` is currently editing —
/// `settingPriceForCloudServer`'s `.sheet(item:)` needs an `Identifiable`,
/// and a plain `Int` (the server id) can't carry the display name/list price
/// the sheet also needs alongside it.
private struct CloudServerPriceTarget: Identifiable {
    let id: Int
    let name: String
    let listPriceMonthly: Decimal?
}

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
    @State private var cloudServerPriceStore = CloudServerPriceStore()
    @State private var isPresentingAddManual = false
    @State private var editingManualEntry: ManualCostEntry?
    @State private var settingPriceForServer: CostsViewModel.DedicatedServerRow?
    @State private var settingPriceForCloudServer: CloudServerPriceTarget?
    @State private var shareImage: Image?
    @State private var csvExportURL: URL?
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
                        heroCard
                        breakdownSection
                        dedicatedAndManualSection
                        invoicesRow
                    }
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.vertical, Spacing.screenMargin)
                    .animation(.smooth, value: manualStore.entries)
                    .animation(.smooth, value: dedicatedPriceStore.entries)
                    .animation(.smooth, value: cloudServerPriceStore.entries)
                    .animation(.snappy, value: scopedProjectID)
                }
                .refreshable {
                    await viewModel.refresh(
                        container: container, manualEntries: manualStore.entries, dedicatedPrices: dedicatedPriceStore.entries,
                        cloudServerPrices: cloudServerPriceStore.entries
                    )
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
                    if shareImage != nil || csvExportURL != nil {
                        Menu {
                            if let shareImage {
                                ShareLink(
                                    item: shareImage,
                                    preview: SharePreview("Hetzly — \(monthTitle) costs", image: shareImage)
                                ) {
                                    Label("Share Image", systemImage: "photo")
                                }
                            }
                            if let csvExportURL {
                                ShareLink(item: csvExportURL) {
                                    Label("Export CSV", systemImage: "tablecells")
                                }
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share Costs")
                        .tint(HetzlyColors.accent)
                    }
                }
            }
        }
        .task {
            resetScopeIfProjectMissing()
            await viewModel.load(
                container: container, manualEntries: manualStore.entries, dedicatedPrices: dedicatedPriceStore.entries,
                cloudServerPrices: cloudServerPriceStore.entries
            )
        }
        .onChange(of: container.projectsStore.projects.map(\.id)) { _, _ in
            resetScopeIfProjectMissing()
        }
        .task(id: shareRenderKey) {
            await renderShareCard()
        }
        .task(id: csvRenderKey) {
            renderCSV()
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
                await viewModel.refresh(
                    container: container, manualEntries: manualStore.entries, dedicatedPrices: dedicatedPriceStore.entries,
                    cloudServerPrices: cloudServerPriceStore.entries
                )
            }
        }
        .onChange(of: dedicatedPriceStore.entries) {
            // Same rationale as manual entries above — and `RobotClient`'s
            // own 5-minute response cache means re-fetching Robot servers
            // right after a local price edit doesn't cost a real request.
            Task {
                await viewModel.refresh(
                    container: container, manualEntries: manualStore.entries, dedicatedPrices: dedicatedPriceStore.entries,
                    cloudServerPrices: cloudServerPriceStore.entries
                )
            }
        }
        .onChange(of: cloudServerPriceStore.entries) {
            // Same rationale as the two stores above — a Cloud server price
            // override is purely a local recompute (no new network calls
            // needed for pricing/servers, both already cached this pass).
            Task {
                await viewModel.refresh(
                    container: container, manualEntries: manualStore.entries, dedicatedPrices: dedicatedPriceStore.entries,
                    cloudServerPrices: cloudServerPriceStore.entries
                )
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
        .sheet(item: $settingPriceForCloudServer) { target in
            CloudServerPriceSheet(
                store: cloudServerPriceStore,
                currency: viewModel.currency,
                serverNumber: target.id,
                serverName: target.name,
                listPriceMonthly: target.listPriceMonthly
            )
        }
        .sheet(isPresented: $isPresentingAddProject) {
            AddProjectSheet()
        }
    }

    // MARK: - Body sections (split out to keep the type-checker fast)

    private var heroCard: some View {
        let hero = viewModel.heroSummary(forProjectID: scopedProjectID)
        return CostsHeroCard(
            monthToDate: hero.monthToDate,
            projected: hero.projected,
            currency: viewModel.currency,
            monthElapsedFraction: viewModel.monthElapsedFraction
        )
    }

    @ViewBuilder
    private var breakdownSection: some View {
        if viewModel.isEmpty && !viewModel.isLoading {
            emptyState
        } else {
            if visibleKindShares.count > 1 {
                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.unit * 4) {
                        SectionLabel("Spend by kind")
                        CostKindDonutChart(shares: visibleKindShares, currency: viewModel.currency)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            ForEach(visibleProjectSections) { section in
                CostProjectSectionView(
                    section: section,
                    currency: viewModel.currency,
                    cloudServerListPrices: viewModel.cloudServerListPrices,
                    cloudServerOverrides: viewModel.cloudServerOverrides,
                    onEditCloudServerPrice: { id, name, listPrice in
                        settingPriceForCloudServer = CloudServerPriceTarget(id: id, name: name, listPriceMonthly: listPrice)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var dedicatedAndManualSection: some View {
        // Dedicated servers and manual entries aren't tied to any Cloud
        // project, so they only make sense in the combined "All" view.
        if scopedProjectID == nil {
            DedicatedCostSection(
                dedicatedServers: viewModel.dedicatedServers,
                dedicatedErrorMessage: viewModel.dedicatedErrorMessage,
                dedicatedIsAuthError: viewModel.dedicatedIsAuthError,
                manualEntries: manualStore.entries,
                currency: viewModel.currency,
                onSetPrice: { settingPriceForServer = $0 },
                onAddManual: { isPresentingAddManual = true },
                onEditManual: { editingManualEntry = $0 },
                onDeleteManual: { removeManualEntry($0) }
            )
        } else if hasScopedHiddenCosts {
            Text("Dedicated & manual costs are shown under All")
                .caption()
        }
    }

    // MARK: - Project scope

    private var scopedProjectID: UUID? {
        selectedProjectID.wrappedValue
    }

    /// Clears the persisted scope back to "All" when it points at a project
    /// that no longer exists, so Costs never renders a blank/underreporting
    /// screen (mirrors the Dashboard/Resources fallback).
    private func resetScopeIfProjectMissing() {
        guard let scoped = scopedProjectID else { return }
        if !container.projectsStore.projects.contains(where: { $0.id == scoped }) {
            selectedProjectIDStorage = ""
        }
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

    /// Whether `DedicatedCostSection` would have something to show if scope
    /// weren't hiding it — gates the "shown under All" footnote so it never
    /// appears for a user who has no dedicated/manual costs to begin with.
    private var hasScopedHiddenCosts: Bool {
        !viewModel.dedicatedServers.isEmpty || !manualStore.entries.isEmpty
    }

    // MARK: - Invoices

    private var invoicesRow: some View {
        NavigationLink {
            InvoicesView()
        } label: {
            GlassCard(interactive: true) {
                HStack(spacing: Spacing.unit * 3) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(HetzlyColors.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Invoices").bodyPrimary()
                        Text("Official Hetzner portal — opens in secure browser").caption()
                    }
                    Spacer(minLength: Spacing.unit * 2)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HetzlyColors.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("costs.invoicesRow")
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

    // MARK: - CSV export

    /// Re-render whenever the numbers the CSV reports change, mirroring
    /// `shareRenderKey` above.
    private var csvRenderKey: String {
        let sections = viewModel.projectSections.map { "\($0.projectName)=\($0.projectedTotal)" }.joined(separator: ",")
        let dedicated = dedicatedPriceStore.entries.map { "\($0.serverNumber)=\($0.monthlyPrice)" }.joined(separator: ",")
        let manual = manualStore.entries.map { "\($0.id)=\($0.monthlyPrice)" }.joined(separator: ",")
        return "\(sections)|\(dedicated)|\(manual)|\(viewModel.currency)"
    }

    private func renderCSV() {
        let rows = CostsCSVExporter.rows(
            projectSections: viewModel.projectSections,
            manualEntries: manualStore.entries,
            dedicatedServers: viewModel.dedicatedServers,
            currency: viewModel.currency
        )
        guard !rows.isEmpty else {
            csvExportURL = nil
            return
        }
        csvExportURL = try? CostsCSVExporter.writeTempFile(rows: rows)
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
