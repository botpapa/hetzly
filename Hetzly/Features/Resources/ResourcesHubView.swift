import SwiftUI

/// Entry point for the Resources tab: a project-scoped hub listing every
/// non-server Hetzner Cloud resource category. Binding entry point per
/// `CONTRACTS.md` — reads `AppContainer` from the environment and owns its
/// own `NavigationStack`.
///
/// Owns the single `ResourcesProjectSelection` instance for this tab and
/// injects it via `.environment` so every pushed screen (including Worker
/// B3's Firewalls/Load Balancers/DNS screens) reads the same selection.
///
/// Project picker: uses `ProjectFilterBar` — the same chips-with-"All"
/// widget Dashboard and Costs scope themselves with (>6 projects collapses
/// into the same menu chip on all three tabs) — in place of the old
/// `ProjectPickerChip` toolbar chip, per the Wave B "picker unity" contract.
/// Resources fundamentally needs ONE project to list resources for (there's
/// no such thing as an "All-projects" volumes list), so unlike Dashboard/
/// Costs, tapping "All" here doesn't aggregate anything — it shows
/// `selectProjectState` instead of the category list. That keeps the visual
/// chrome and interaction model identical across all three tabs (same
/// component, same collapse behavior) while staying honest that Resources
/// is still single-select underneath.
struct ResourcesHubView: View {
    @Environment(AppContainer.self) private var container
    @State private var selection = ResourcesProjectSelection()
    @State private var viewModel = ResourcesHubViewModel()
    @State private var isAddProjectPresented = false

    /// Remembers the scoped project across launches (stored as a `String`
    /// since `AppStorage` has no native `UUID?` support). Read once on
    /// appear to seed `selection.projectID`; written back whenever the user
    /// switches projects via `ProjectFilterBar`. Deliberately never
    /// persists "All" (`nil`) — see `resolvedInitialProjectID()`.
    @AppStorage("resources.selectedProject") private var persistedProjectIDStorage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()

                if container.projectsStore.projects.isEmpty {
                    noProjectsState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.unit * 5) {
                            ProjectFilterBar(
                                projects: container.projectsStore.projects,
                                selection: $selection.projectID,
                                onAddProject: { isAddProjectPresented = true }
                            )

                            if selection.projectID == nil {
                                selectProjectState
                            } else {
                                if let errorMessage = viewModel.errorMessage {
                                    ResourceErrorBanner(message: errorMessage)
                                }

                                infrastructureSection
                                networkingSection
                                accessSection
                                storageSection
                            }
                        }
                        .padding(.horizontal, Spacing.screenMargin)
                        .padding(.vertical, Spacing.screenMargin)
                    }
                    .refreshable {
                        await viewModel.load(projectID: selection.projectID, container: container)
                    }
                }
            }
            .navigationTitle("Resources")
        }
        .environment(selection)
        .sheet(isPresented: $isAddProjectPresented) {
            AddProjectSheet()
        }
        .task {
            if selection.projectID == nil {
                selection.projectID = resolvedInitialProjectID()
            }
            await viewModel.loadIfNeeded(projectID: selection.projectID, container: container)
        }
        .onChange(of: selection.projectID) { _, newValue in
            persistedProjectIDStorage = newValue?.uuidString ?? ""
            Task { await viewModel.load(projectID: newValue, container: container) }
        }
        .onChange(of: container.projectsStore.projects.map(\.id)) { _, currentIDs in
            // The scoped project may have been removed (Settings) while
            // Resources was showing it — fall back to the first remaining
            // project rather than staying scoped to nothing.
            if let current = selection.projectID, !currentIDs.contains(current) {
                selection.projectID = currentIDs.first
            }
        }
    }

    /// The project to scope to on first appearance: the persisted selection
    /// if it still exists, otherwise the first project — gracefully
    /// recovering if that project was deleted since the last launch.
    private func resolvedInitialProjectID() -> UUID? {
        let projects = container.projectsStore.projects
        if let stored = UUID(uuidString: persistedProjectIDStorage), projects.contains(where: { $0.id == stored }) {
            return stored
        }
        return projects.first?.id
    }

    // MARK: - No projects

    private var noProjectsState: some View {
        VStack(spacing: Spacing.unit * 5) {
            if container.settings.mascotEnabled {
                MascotView(state: .peek, scale: 4)
            } else {
                Image(systemName: "tray")
                    .font(.system(size: 40))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
            VStack(spacing: Spacing.unit * 2) {
                SectionLabel("No Projects")
                Text("Add a project in Settings to manage its volumes, networks, and more.")
                    .bodySecondary()
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.unit * 16)
    }

    // MARK: - "All" selected

    /// Shown instead of the category list when `ProjectFilterBar`'s "All"
    /// chip is selected. Unlike Dashboard/Costs, Resources has no
    /// combined-across-projects view to fall back to — every category list
    /// (volumes, networks, SSH keys, …) is inherently scoped to one
    /// project's `CloudClient` — so this is a deliberate prompt rather than
    /// an aggregation.
    private var selectProjectState: some View {
        VStack(spacing: Spacing.unit * 5) {
            if container.settings.mascotEnabled {
                MascotView(state: .peek, scale: 4)
            } else {
                Image(systemName: "cube.box")
                    .font(.system(size: 40))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
            VStack(spacing: Spacing.unit * 2) {
                SectionLabel("Select a Project")
                Text("Resources are scoped to one project at a time — choose one above to see its volumes, networks, and more.")
                    .bodySecondary()
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.unit * 10)
    }

    // MARK: - Sections

    private var infrastructureSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            SectionLabel("Infrastructure")

            NavigationLink {
                VolumesListView()
            } label: {
                ResourceHubRow(title: "Volumes", systemImage: "externaldrive", count: viewModel.counts.volumes)
            }
            .buttonStyle(.plain)

            NavigationLink {
                NetworksListView()
            } label: {
                ResourceHubRow(title: "Networks", systemImage: "point.3.connected.trianglepath.dotted", count: viewModel.counts.networks)
            }
            .buttonStyle(.plain)

            NavigationLink {
                PlacementGroupsListView()
            } label: {
                ResourceHubRow(title: "Placement Groups", systemImage: "square.stack.3d.up", count: viewModel.counts.placementGroups)
            }
            .buttonStyle(.plain)
        }
    }

    private var networkingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            SectionLabel("Networking")

            NavigationLink {
                PrimaryIPsListView()
            } label: {
                ResourceHubRow(title: "Primary IPs", systemImage: "network", count: viewModel.counts.primaryIPs)
            }
            .buttonStyle(.plain)

            NavigationLink {
                FloatingIPsListView()
            } label: {
                ResourceHubRow(title: "Floating IPs", systemImage: "arrow.triangle.branch", count: viewModel.counts.floatingIPs)
            }
            .buttonStyle(.plain)

            NavigationLink {
                FirewallListView()
            } label: {
                ResourceHubRow(title: "Firewalls", systemImage: "shield", count: nil)
            }
            .buttonStyle(.plain)

            NavigationLink {
                LoadBalancerListView()
            } label: {
                ResourceHubRow(title: "Load Balancers", systemImage: "arrow.left.arrow.right.circle", count: nil)
            }
            .buttonStyle(.plain)

            NavigationLink {
                DNSZoneListView()
            } label: {
                ResourceHubRow(title: "DNS", systemImage: "globe", count: nil)
            }
            .buttonStyle(.plain)
        }
    }

    private var accessSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            SectionLabel("Access")

            NavigationLink {
                SSHKeysListView()
            } label: {
                ResourceHubRow(title: "SSH Keys", systemImage: "key", count: viewModel.counts.sshKeys)
            }
            .buttonStyle(.plain)

            NavigationLink {
                CertificatesListView()
            } label: {
                ResourceHubRow(title: "Certificates", systemImage: "checkmark.seal", count: viewModel.counts.certificates)
            }
            .buttonStyle(.plain)
        }
    }

    /// Storage Boxes are account-scoped (Hetzner's separate api.hetzner.com
    /// platform), not project-scoped — the row lives here for discoverability
    /// but the screen manages its own account selection.
    private var storageSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            SectionLabel("Storage")

            NavigationLink {
                StorageBoxesView()
            } label: {
                ResourceHubRow(title: "Storage Boxes", systemImage: "externaldrive", count: nil)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    ResourcesHubView()
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}
