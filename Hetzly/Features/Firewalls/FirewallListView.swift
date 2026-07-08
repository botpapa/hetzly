import HetznerKit
import SwiftUI

/// Firewalls for the currently selected project (read from
/// `ResourcesProjectSelection` in the environment). Pushed from Worker B2's
/// Resources hub inside its `NavigationStack`. Rows navigate to
/// `FirewallDetailView`; swipe-to-delete confirms (and gates behind
/// Face ID / Touch ID when enabled in Settings).
struct FirewallListView: View {
    @Environment(AppContainer.self) private var container
    @Environment(ResourcesProjectSelection.self) private var projectSelection

    @State private var viewModel: FirewallListViewModel?
    @State private var isCreateSheetPresented = false
    @State private var pendingDeletion: Firewall?
    @State private var isAuthenticating = false
    @State private var pushedRoute: FirewallRoute?

    init() {}

    /// Push target for detail. `Firewall` itself isn't `Hashable` (the wire
    /// model is only `Equatable`), so navigation routes on the id and the
    /// detail view picks up its initial snapshot from the loaded list.
    private struct FirewallRoute: Hashable {
        let firewallID: Int
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            content
        }
        .navigationTitle("Firewalls")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCreateSheetPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(projectSelection.projectID == nil)
            }
        }
        .task(id: projectSelection.projectID) {
            await reloadForSelectedProject()
        }
        .sheet(isPresented: $isCreateSheetPresented) {
            CreateFirewallSheet(
                onCreate: { name in
                    await viewModel?.create(name: name) ?? .failure(DisplayError("Select a project first."))
                },
                onCreated: { firewall in
                    // Go straight to detail so the user can add rules — the
                    // create sheet intentionally collects only a name.
                    pushedRoute = FirewallRoute(firewallID: firewall.id)
                }
            )
        }
        .navigationDestination(item: $pushedRoute) { route in
            if let projectID = viewModel?.projectID {
                FirewallDetailView(
                    projectID: projectID,
                    firewallID: route.firewallID,
                    initialFirewall: viewModel?.firewalls.first { $0.id == route.firewallID }
                )
            }
        }
        .confirmationDialog(
            "Delete Firewall",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete \"\(pendingDeletion?.name ?? "")\"", role: .destructive) {
                confirmDeletion()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The firewall is removed from every server it's applied to. This cannot be undone.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if projectSelection.projectID == nil {
            emptyState(
                message: "Pick a project to see its firewalls.",
                showsCreate: false
            )
        } else if let viewModel {
            switch viewModel.loadState {
            case .idle, .loading:
                if viewModel.firewalls.isEmpty {
                    loadingState
                } else {
                    list(viewModel)
                }
            case .failed(let message):
                if viewModel.firewalls.isEmpty {
                    errorState(message)
                } else {
                    list(viewModel)
                }
            case .loaded:
                if viewModel.firewalls.isEmpty {
                    emptyState(
                        message: "No firewalls yet. Create one to control traffic to your servers.",
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
            MascotView(state: .idle, scale: 3)
            Text("Loading firewalls…").caption()
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Spacing.unit * 4) {
            MascotView(state: .alarm, scale: 3)
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
            MascotView(state: .peek, scale: 3)
            Text(message)
                .bodySecondary()
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.screenMargin * 2)
            if showsCreate {
                PrimaryCTA(title: "Create Firewall") {
                    isCreateSheetPresented = true
                }
            }
        }
    }

    private func list(_ viewModel: FirewallListViewModel) -> some View {
        List {
            if let deletionError = viewModel.deletionError {
                Text(deletionError)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HetzlyColors.destructive)
                    .plainRow()
            }

            ForEach(viewModel.firewalls) { firewall in
                Button {
                    pushedRoute = FirewallRoute(firewallID: firewall.id)
                } label: {
                    FirewallRowView(firewall: firewall)
                }
                .buttonStyle(.plain)
                .plainRow()
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDeletion = firewall
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

    // MARK: - Lifecycle

    private func reloadForSelectedProject() async {
        guard let projectID = projectSelection.projectID else {
            viewModel = nil
            return
        }
        if viewModel?.projectID != projectID {
            viewModel = FirewallListViewModel(projectID: projectID, container: container)
        }
        await viewModel?.load()
    }

    // MARK: - Deletion

    private func confirmDeletion() {
        guard let firewall = pendingDeletion else { return }
        pendingDeletion = nil

        Task {
            if container.settings.requireBiometricsForDestructive {
                isAuthenticating = true
                let approved = await container.biometricGate.authenticate(
                    reason: "Confirm deleting the firewall \"\(firewall.name)\""
                )
                isAuthenticating = false
                guard approved else { return }
            }
            await viewModel?.delete(firewall)
        }
    }
}

#Preview {
    NavigationStack {
        FirewallListView()
            .environment(AppContainer.makeDefault())
            .environment(ResourcesProjectSelection())
    }
    .preferredColorScheme(.dark)
}
