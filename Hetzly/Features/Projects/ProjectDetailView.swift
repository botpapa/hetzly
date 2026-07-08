import SwiftUI

/// The per-project command center: tap a project anywhere in the app (a
/// Dashboard or Costs project section header, per the multi-project wave
/// contract) and manage everything about it from one screen — burn, its
/// servers, a resource-count overview, its top costs, and project-level
/// management (rename, update token, remove).
///
/// Reads `AppContainer` from the environment. Binding entry point per
/// `CONTRACTS.md`'s multi-project wave contract: `init(route: ProjectRoute)`.
///
/// ## Navigation
/// This view is always pushed *inside* a host's own `NavigationStack`
/// (Dashboard's or Costs') via that host's `.navigationDestination(for:
/// ProjectRoute.self)`. Registering a second `.navigationDestination(for:
/// ServerRoute.self)` here would double-register that destination type on
/// the same stack (Dashboard already registers one) — a runtime warning and,
/// per SwiftUI's own docs, undefined-which-one-wins behavior. Server rows
/// instead navigate through local `@State` + `.navigationDestination(item:)`,
/// which is keyed structurally (an `Optional<ServerRoute>` binding) rather
/// than by registering `ServerRoute.self` a second time, so it coexists
/// safely with whatever the host stack has already registered.
struct ProjectDetailView: View {
    let route: ProjectRoute

    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: ProjectDetailViewModel?
    /// Preview-only stand-in for the `ProjectRecord` that would otherwise be
    /// looked up from `container.projectsStore.projects` — previews don't
    /// seed a real SwiftData store. `nil` in every real launch.
    @State private var previewProject: ProjectRecord?

    @State private var selectedServerRoute: ServerRoute?
    @State private var isCreateServerPresented = false
    @State private var isRenamePresented = false
    @State private var renameText = ""
    @State private var isPendingRemoval = false
    @State private var isUpdateTokenPresented = false
    @State private var actionError: String?

    init(route: ProjectRoute) {
        self.route = route
    }

    /// Preview/test-only entry point: injects a pre-populated view model and
    /// an unpersisted `ProjectRecord` standing in for the store lookup, so
    /// previews never touch the network or need a seeded `AppContainer`.
    init(route: ProjectRoute, previewViewModel: ProjectDetailViewModel, previewProject: ProjectRecord) {
        self.route = route
        _viewModel = State(initialValue: previewViewModel)
        _previewProject = State(initialValue: previewProject)
    }

    private var project: ProjectRecord? {
        previewProject ?? container.projectsStore.projects.first(where: { $0.id == route.projectID })
    }

    var body: some View {
        ZStack(alignment: .top) {
            CanvasBackground()
            body(for: viewModel)
        }
        .navigationTitle(project?.name ?? "Project")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedServerRoute) { route in
            ServerDetailView(route: route)
        }
        .task {
            guard viewModel == nil else { return }
            let model = ProjectDetailViewModel(projectID: route.projectID)
            viewModel = model
            await model.load(container: container)
        }
        .sheet(isPresented: $isCreateServerPresented) {
            CreateServerFlow(projectID: route.projectID) { _ in
                Task { await viewModel?.refresh(container: container) }
            }
        }
        .sheet(isPresented: $isUpdateTokenPresented) {
            if let project {
                UpdateTokenSheet(project: project)
            }
        }
        .alert("Rename Project", isPresented: $isRenamePresented) {
            TextField("Project name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { commitRename() }
        }
        .confirmationDialog("Remove Project", isPresented: $isPendingRemoval, titleVisibility: .visible) {
            Button("Remove from Hetzly", role: .destructive) { commitRemoval() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This only removes \"\(project?.name ?? "this project")\" from Hetzly. Nothing is touched on Hetzner.")
        }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func body(for viewModel: ProjectDetailViewModel?) -> some View {
        if let viewModel {
            switch viewModel.loadState {
            case .idle, .loading:
                if viewModel.servers.isEmpty {
                    loadingState
                } else {
                    loadedContent(viewModel)
                }
            case .failed(let message):
                if viewModel.servers.isEmpty {
                    errorState(message)
                } else {
                    loadedContent(viewModel)
                }
            case .loaded:
                loadedContent(viewModel)
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
            Text("Loading project…").caption()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, Spacing.unit * 16)
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
                Task { await viewModel?.refresh(container: container) }
            }
            .secondaryCTAStyle()
            if viewModel?.missingToken == true {
                Button("Update API Token") { isUpdateTokenPresented = true }
                    .primaryCTAStyle()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, Spacing.unit * 12)
    }

    @ViewBuilder
    private func loadedContent(_ viewModel: ProjectDetailViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.unit * 8) {
                if viewModel.isStale {
                    GlassChip("Showing cached data", systemImage: "clock.arrow.circlepath")
                }

                if viewModel.missingToken {
                    tokenRevokedBanner
                } else if !viewModel.resourceErrors.isEmpty {
                    resourceErrorsBanner(viewModel.resourceErrors)
                }

                BurnCardView(
                    monthToDate: viewModel.monthToDate,
                    projected: viewModel.projected,
                    currency: viewModel.currency,
                    idleMascotState: nil
                )

                serversSection(viewModel)

                ProjectResourcesSection(counts: viewModel.counts)

                ProjectCostsSection(items: viewModel.topCostItems, currency: viewModel.currency)

                ProjectManageSection(
                    onRename: {
                        renameText = project?.name ?? ""
                        isRenamePresented = true
                    },
                    onUpdateToken: { isUpdateTokenPresented = true },
                    onRemove: { isPendingRemoval = true }
                )
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.vertical, Spacing.screenMargin)
        }
        .refreshable {
            await viewModel.refresh(container: container)
        }
    }

    // MARK: - Servers section

    @ViewBuilder
    private func serversSection(_ viewModel: ProjectDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            SectionLabel("Servers")

            if viewModel.servers.isEmpty {
                GlassCard {
                    Text("No servers in this project")
                        .bodySecondary()
                }
            } else {
                VStack(spacing: Spacing.unit * 2) {
                    ForEach(viewModel.servers) { item in
                        Button {
                            selectedServerRoute = ServerRoute(projectID: item.projectID, serverID: item.serverID)
                        } label: {
                            ServerRowView(item: item, cpuSamples: nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            PrimaryCTA(title: "Create Server in \(project?.name ?? "This Project")") {
                isCreateServerPresented = true
            }
        }
    }

    // MARK: - Banners

    private var tokenRevokedBanner: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                HStack(spacing: Spacing.unit * 2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(HetzlyColors.statusError)
                    Text("No stored credentials for this project.")
                        .bodySecondary()
                }
                Button("Update API Token") { isUpdateTokenPresented = true }
                    .secondaryCTAStyle()
            }
        }
    }

    private func resourceErrorsBanner(_ messages: [String]) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                ForEach(messages, id: \.self) { message in
                    HStack(spacing: Spacing.unit * 2) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(HetzlyColors.statusError)
                        Text(message)
                            .bodySecondary()
                    }
                }
            }
        }
    }

    // MARK: - Rename

    private func commitRename() {
        guard let project else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        container.projectsStore.rename(project, to: trimmed)
    }

    // MARK: - Removal

    private func commitRemoval() {
        guard let project else { return }
        Task {
            if container.settings.requireBiometricsForDestructive {
                let approved = await container.biometricGate.authenticate(
                    reason: "Confirm removing \"\(project.name)\" from Hetzly"
                )
                guard approved else { return }
            }
            do {
                try container.projectsStore.remove(project)
                dismiss()
            } catch {
                actionError = "Couldn't remove this project. Please try again."
            }
        }
    }
}

#Preview("Loaded") {
    NavigationStack {
        ProjectDetailView(
            route: ProjectRoute(projectID: ProjectsPreviewFixtures.projectID),
            previewViewModel: ProjectsPreviewFixtures.loadedViewModel,
            previewProject: ProjectsPreviewFixtures.project
        )
        .environment(AppContainer.makeDefault())
    }
    .preferredColorScheme(.dark)
}

#Preview("Stale / partial errors") {
    NavigationStack {
        ProjectDetailView(
            route: ProjectRoute(projectID: ProjectsPreviewFixtures.projectID),
            previewViewModel: ProjectsPreviewFixtures.staleViewModel,
            previewProject: ProjectsPreviewFixtures.project
        )
        .environment(AppContainer.makeDefault())
    }
    .preferredColorScheme(.dark)
}

#Preview("Empty project") {
    NavigationStack {
        ProjectDetailView(
            route: ProjectRoute(projectID: ProjectsPreviewFixtures.projectID),
            previewViewModel: ProjectsPreviewFixtures.emptyViewModel,
            previewProject: ProjectsPreviewFixtures.project
        )
        .environment(AppContainer.makeDefault())
    }
    .preferredColorScheme(.dark)
}

#Preview("Token revoked") {
    NavigationStack {
        ProjectDetailView(
            route: ProjectRoute(projectID: ProjectsPreviewFixtures.projectID),
            previewViewModel: ProjectsPreviewFixtures.missingTokenViewModel,
            previewProject: ProjectsPreviewFixtures.project
        )
        .environment(AppContainer.makeDefault())
    }
    .preferredColorScheme(.dark)
}
