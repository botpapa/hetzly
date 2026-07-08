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
                        CostsHeroCard(
                            monthToDate: viewModel.combinedMonthToDate,
                            projected: viewModel.combinedProjected,
                            currency: viewModel.currency,
                            monthElapsedFraction: viewModel.monthElapsedFraction
                        )

                        if viewModel.isEmpty && !viewModel.isLoading {
                            emptyState
                        } else {
                            if viewModel.kindShares.count > 1 {
                                GlassCard {
                                    VStack(alignment: .leading, spacing: Spacing.unit * 4) {
                                        SectionLabel("Spend by kind")
                                        CostKindDonutChart(
                                            shares: viewModel.kindShares,
                                            currency: viewModel.currency
                                        )
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }

                            ForEach(viewModel.projectSections) { section in
                                CostProjectSectionView(section: section, currency: viewModel.currency)
                            }
                        }

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
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.vertical, Spacing.screenMargin)
                    .animation(.smooth, value: manualStore.entries)
                    .animation(.smooth, value: dedicatedPriceStore.entries)
                }
                .refreshable {
                    await viewModel.refresh(container: container, manualEntries: manualStore.entries, dedicatedPrices: dedicatedPriceStore.entries)
                }
            }
            .navigationTitle("Costs")
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
