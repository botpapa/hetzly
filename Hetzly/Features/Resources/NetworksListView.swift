import HetznerKit
import SwiftUI

/// Private networks for the selected project.
struct NetworksListView: View {
    @Environment(AppContainer.self) private var container
    @Environment(ResourcesProjectSelection.self) private var selection

    @State private var model = ResourceListModel<Network>(load: { [] })
    @State private var isPresentingCreate = false
    @State private var pendingDelete: Network?
    @State private var actionError: String?

    var body: some View {
        ZStack {
            CanvasBackground()
            resourceListBody(
                state: model.state,
                items: model.items,
                emptyTitle: "No Networks",
                emptyMessage: "Create a private network to connect servers over an internal, unmetered link.",
                emptyCTA: "Create Network",
                onCreate: { isPresentingCreate = true },
                onRetry: { Task { await model.refresh() } },
                onRefresh: { await model.refresh() }
            ) { network in
                NavigationLink {
                    NetworkDetailView(network: network, onChange: { Task { await model.refresh() } })
                } label: {
                    NetworkRow(network: network)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        pendingDelete = network
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Networks")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isPresentingCreate = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Create Network")
            }
        }
        .task(id: selection.projectID) { await reload() }
        .sheet(isPresented: $isPresentingCreate) {
            NetworkCreateSheet(projectID: selection.projectID) {
                Task { await model.refresh() }
            }
        }
        .confirmationDialog(
            "Delete Network",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { commitDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes \"\(pendingDelete?.name ?? "")\". Attached servers lose their private IP on this network.")
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

    private func reload() async {
        guard let projectID = selection.projectID, let client = container.cloudClient(for: projectID) else {
            model = ResourceListModel(load: { [] })
            return
        }
        model = ResourceListModel(load: { try await client.listNetworks() })
        await model.loadIfNeeded()
    }

    private func commitDelete() {
        guard let network = pendingDelete else { return }
        pendingDelete = nil
        guard let projectID = selection.projectID, let client = container.cloudClient(for: projectID) else { return }
        Task {
            let error = await confirmDestructive(
                container: container,
                reason: "Confirm deleting network \"\(network.name)\""
            ) {
                try await client.deleteNetwork(id: network.id)
            }
            if let error {
                actionError = error
            } else {
                await model.refresh()
            }
        }
    }
}

struct NetworkRow: View {
    let network: Network

    var body: some View {
        GlassCard(interactive: true) {
            HStack(spacing: Spacing.unit * 3) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(HetzlyColors.textSecondary)

                VStack(alignment: .leading, spacing: Spacing.unit) {
                    Text(network.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(HetzlyColors.textPrimary)
                    Text(network.ipRange)
                        .hetzlyMonoNumbers()
                        .foregroundStyle(HetzlyColors.textSecondary)
                }

                Spacer(minLength: Spacing.unit * 2)

                GlassChip("\(network.servers.count)", systemImage: "server.rack")
            }
        }
    }
}

#Preview {
    NavigationStack {
        ZStack {
            CanvasBackground()
            VStack(spacing: Spacing.unit * 3) {
                ForEach(ResourcesPreviewFixtures.networks) { network in
                    NetworkRow(network: network)
                }
            }
            .padding(Spacing.screenMargin)
        }
    }
    .preferredColorScheme(.dark)
}
