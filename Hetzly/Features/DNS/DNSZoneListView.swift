import HetznerKit
import SwiftUI

/// DNS zones for the currently selected project (read from
/// `ResourcesProjectSelection` in the environment). Pushed from Worker B2's
/// Resources hub inside its `NavigationStack`. Deletion is deliberately
/// heavy: swipe → type-the-zone-name sheet (+ Face ID when enabled) —
/// deleting a zone takes a whole domain offline.
struct DNSZoneListView: View {
    @Environment(AppContainer.self) private var container
    @Environment(ResourcesProjectSelection.self) private var projectSelection

    @State private var viewModel: DNSZoneListViewModel?
    @State private var isCreateSheetPresented = false
    @State private var pendingDeletion: DNSZone?
    @State private var isAuthenticating = false
    @State private var pushedRoute: ZoneRoute?

    init() {}

    /// `DNSZone` isn't `Hashable`, so navigation routes on the id.
    private struct ZoneRoute: Hashable {
        let zoneID: Int
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            content
        }
        .navigationTitle("DNS")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCreateSheetPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create DNS Zone")
                .disabled(projectSelection.projectID == nil)
            }
        }
        .task(id: projectSelection.projectID) {
            await reloadForSelectedProject()
        }
        .sheet(isPresented: $isCreateSheetPresented) {
            CreateZoneSheet(
                onCreate: { name, ttl in
                    await viewModel?.create(name: name, ttl: ttl) ?? .failure(DisplayError("Select a project first."))
                },
                onCreated: { zone in
                    pushedRoute = ZoneRoute(zoneID: zone.id)
                }
            )
        }
        .sheet(item: $pendingDeletion) { zone in
            DeleteZoneConfirmSheet(
                zone: zone,
                isAuthenticating: isAuthenticating,
                onConfirm: { confirmDeletion(zone) },
                onCancel: { pendingDeletion = nil }
            )
        }
        .navigationDestination(item: $pushedRoute) { route in
            if let projectID = viewModel?.projectID {
                DNSZoneDetailView(
                    projectID: projectID,
                    zoneID: route.zoneID,
                    initialZone: viewModel?.zones.first { $0.id == route.zoneID }
                )
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if projectSelection.projectID == nil {
            emptyState(message: "Pick a project to see its DNS zones.", showsCreate: false)
        } else if let viewModel {
            switch viewModel.loadState {
            case .idle, .loading:
                if viewModel.zones.isEmpty { loadingState } else { list(viewModel) }
            case .failed(let message):
                if viewModel.zones.isEmpty { errorState(message) } else { list(viewModel) }
            case .loaded:
                if viewModel.zones.isEmpty {
                    emptyState(
                        message: "No DNS zones yet. Add one to manage a domain's records here.",
                        showsCreate: true
                    )
                } else {
                    list(viewModel)
                }
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
            Text("Loading zones…").caption()
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

    private func emptyState(message: String, showsCreate: Bool) -> some View {
        VStack(spacing: Spacing.unit * 4) {
            if container.settings.mascotEnabled {
                MascotView(state: .peek, scale: 3)
            } else {
                Image(systemName: "tray")
                    .font(.system(size: 40))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
            Text(message)
                .bodySecondary()
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.screenMargin * 2)
            if showsCreate {
                PrimaryCTA(title: "Add Zone") {
                    isCreateSheetPresented = true
                }
            }
        }
    }

    private func list(_ viewModel: DNSZoneListViewModel) -> some View {
        List {
            if let deletionError = viewModel.deletionError {
                Text(deletionError)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HetzlyColors.destructive)
                    .plainRow()
            }

            ForEach(viewModel.zones) { zone in
                Button {
                    pushedRoute = ZoneRoute(zoneID: zone.id)
                } label: {
                    zoneRow(zone)
                }
                .buttonStyle(.plain)
                .plainRow()
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDeletion = zone
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await viewModel.load() }
    }

    private func zoneRow(_ zone: DNSZone) -> some View {
        GlassCard(interactive: true) {
            HStack(spacing: Spacing.unit * 3) {
                StatusDot(zone.status.resourceStatus)

                VStack(alignment: .leading, spacing: Spacing.unit) {
                    Text(zone.name)
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .foregroundStyle(HetzlyColors.textPrimary)

                    HStack(spacing: Spacing.unit * 2) {
                        GlassChip("\(zone.recordCount) record\(zone.recordCount == 1 ? "" : "s")")
                        Text(zone.status.displayName).caption()
                    }
                }

                Spacer(minLength: Spacing.unit * 2)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
        }
    }

    // MARK: - Lifecycle

    private func reloadForSelectedProject() async {
        guard let projectID = projectSelection.projectID else {
            viewModel = nil
            return
        }
        if viewModel?.projectID != projectID {
            viewModel = DNSZoneListViewModel(projectID: projectID, container: container)
        }
        await viewModel?.load()
    }

    // MARK: - Deletion

    private func confirmDeletion(_ zone: DNSZone) {
        Task {
            if container.settings.requireBiometricsForDestructive {
                isAuthenticating = true
                let approved = await container.biometricGate.authenticate(
                    reason: "Confirm deleting the DNS zone \(zone.name)"
                )
                isAuthenticating = false
                guard approved else { return }
            }
            pendingDeletion = nil
            await viewModel?.delete(zone)
        }
    }
}

#Preview {
    NavigationStack {
        DNSZoneListView()
            .environment(AppContainer.makeDefault())
            .environment(ResourcesProjectSelection())
    }
    .preferredColorScheme(.dark)
}
