import SwiftUI

/// Entry point for the Resources tab: a project-scoped hub listing every
/// non-server Hetzner Cloud resource category. Binding entry point per
/// `CONTRACTS.md` — reads `AppContainer` from the environment and owns its
/// own `NavigationStack`.
///
/// Owns the single `ResourcesProjectSelection` instance for this tab and
/// injects it via `.environment` so every pushed screen (including Worker
/// B3's Firewalls/Load Balancers/DNS screens) reads the same selection.
struct ResourcesHubView: View {
    @Environment(AppContainer.self) private var container
    @State private var selection = ResourcesProjectSelection()
    @State private var viewModel = ResourcesHubViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()

                if container.projectsStore.projects.isEmpty {
                    noProjectsState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.unit * 5) {
                            if let errorMessage = viewModel.errorMessage {
                                ResourceErrorBanner(message: errorMessage)
                            }

                            infrastructureSection
                            networkingSection
                            accessSection
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProjectPickerChip(projects: container.projectsStore.projects, selection: $selection.projectID)
                }
            }
        }
        .environment(selection)
        .task {
            if selection.projectID == nil {
                selection.projectID = container.projectsStore.projects.first?.id
            }
            await viewModel.loadIfNeeded(projectID: selection.projectID, container: container)
        }
        .onChange(of: selection.projectID) { _, newValue in
            Task { await viewModel.load(projectID: newValue, container: container) }
        }
    }

    // MARK: - No projects

    private var noProjectsState: some View {
        VStack(spacing: Spacing.unit * 5) {
            MascotView(state: .peek, scale: 4)
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
}

#Preview {
    ResourcesHubView()
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}
