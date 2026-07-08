import HetznerKit
import SwiftUI

/// Load balancers for the currently selected project (read from
/// `ResourcesProjectSelection` in the environment). Pushed from Worker B2's
/// Resources hub inside its `NavigationStack`.
struct LoadBalancerListView: View {
    @Environment(AppContainer.self) private var container
    @Environment(ResourcesProjectSelection.self) private var projectSelection

    @State private var viewModel: LoadBalancerListViewModel?
    @State private var isCreateSheetPresented = false
    @State private var pendingDeletion: LoadBalancer?
    @State private var pushedRoute: LBRoute?

    init() {}

    /// `LoadBalancer` isn't `Hashable`, so navigation routes on the id.
    private struct LBRoute: Hashable {
        let loadBalancerID: Int
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            content
        }
        .navigationTitle("Load Balancers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCreateSheetPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create Load Balancer")
                .disabled(projectSelection.projectID == nil)
            }
        }
        .task(id: projectSelection.projectID) {
            await reloadForSelectedProject()
        }
        .sheet(isPresented: $isCreateSheetPresented) {
            if let projectID = projectSelection.projectID {
                CreateLoadBalancerSheet(projectID: projectID) { created in
                    Task { await viewModel?.load() }
                    pushedRoute = LBRoute(loadBalancerID: created.id)
                }
            }
        }
        .navigationDestination(item: $pushedRoute) { route in
            if let projectID = viewModel?.projectID {
                LBDetailView(
                    projectID: projectID,
                    loadBalancerID: route.loadBalancerID,
                    initialLoadBalancer: viewModel?.loadBalancers.first { $0.id == route.loadBalancerID }
                )
            }
        }
        .confirmationDialog(
            "Delete Load Balancer",
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
            Text("Traffic will stop being distributed to its targets. This cannot be undone.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if projectSelection.projectID == nil {
            emptyState(message: "Pick a project to see its load balancers.", showsCreate: false)
        } else if let viewModel {
            switch viewModel.loadState {
            case .idle, .loading:
                if viewModel.loadBalancers.isEmpty {
                    loadingState
                } else {
                    list(viewModel)
                }
            case .failed(let message):
                if viewModel.loadBalancers.isEmpty {
                    errorState(message)
                } else {
                    list(viewModel)
                }
            case .loaded:
                if viewModel.loadBalancers.isEmpty {
                    emptyState(
                        message: "No load balancers yet. Create one to distribute traffic across servers.",
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
            Text("Loading load balancers…").caption()
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
                PrimaryCTA(title: "Create Load Balancer") {
                    isCreateSheetPresented = true
                }
            }
        }
    }

    private func list(_ viewModel: LoadBalancerListViewModel) -> some View {
        List {
            if let deletionError = viewModel.deletionError {
                Text(deletionError)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HetzlyColors.destructive)
                    .plainRow()
            }

            ForEach(viewModel.loadBalancers) { loadBalancer in
                Button {
                    pushedRoute = LBRoute(loadBalancerID: loadBalancer.id)
                } label: {
                    LoadBalancerRowView(loadBalancer: loadBalancer)
                }
                .buttonStyle(.plain)
                .plainRow()
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDeletion = loadBalancer
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
            viewModel = LoadBalancerListViewModel(projectID: projectID, container: container)
        }
        await viewModel?.load()
    }

    // MARK: - Deletion

    private func confirmDeletion() {
        guard let loadBalancer = pendingDeletion else { return }
        pendingDeletion = nil

        Task {
            if container.settings.requireBiometricsForDestructive {
                let approved = await container.biometricGate.authenticate(
                    reason: "Confirm deleting the load balancer \"\(loadBalancer.name)\""
                )
                guard approved else { return }
            }
            await viewModel?.delete(loadBalancer)
        }
    }
}

#Preview {
    NavigationStack {
        LoadBalancerListView()
            .environment(AppContainer.makeDefault())
            .environment(ResourcesProjectSelection())
    }
    .preferredColorScheme(.dark)
}
