import HetznerKit
import SwiftUI

/// Block Storage volumes for the selected project: list, create, and (via
/// `VolumeDetailView`) attach/detach, resize, protect, and delete.
struct VolumesListView: View {
    @Environment(AppContainer.self) private var container
    @Environment(ResourcesProjectSelection.self) private var selection

    @State private var model = ResourceListModel<Volume>(load: { [] })
    @State private var isPresentingCreate = false
    @State private var pendingDelete: Volume?
    @State private var actionError: String?

    var body: some View {
        ZStack {
            CanvasBackground()
            resourceListBody(
                state: model.state,
                items: model.items,
                emptyTitle: "No Volumes",
                emptyMessage: "Attach extra Block Storage to any server for more disk space.",
                emptyCTA: "Create Volume",
                onCreate: { isPresentingCreate = true },
                onRetry: { Task { await model.refresh() } },
                onRefresh: { await model.refresh() }
            ) { volume in
                NavigationLink {
                    VolumeDetailView(volume: volume, onChange: { Task { await model.refresh() } })
                } label: {
                    VolumeRow(volume: volume)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        pendingDelete = volume
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Volumes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isPresentingCreate = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Create Volume")
            }
        }
        .task(id: selection.projectID) { await reload() }
        .sheet(isPresented: $isPresentingCreate) {
            VolumeCreateSheet(projectID: selection.projectID) {
                Task { await model.refresh() }
            }
        }
        .confirmationDialog(
            "Delete Volume",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { commitDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes \"\(pendingDelete?.name ?? "")\" and all data on it.")
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
        model = ResourceListModel(load: { try await client.listVolumes() })
        await model.loadIfNeeded()
    }

    private func commitDelete() {
        guard let volume = pendingDelete else { return }
        pendingDelete = nil
        guard let projectID = selection.projectID, let client = container.cloudClient(for: projectID) else { return }
        Task {
            let error = await confirmDestructive(
                container: container,
                reason: "Confirm deleting volume \"\(volume.name)\""
            ) {
                try await client.deleteVolume(id: volume.id)
            }
            if let error {
                actionError = error
            } else {
                await model.refresh()
            }
        }
    }
}

/// A single volume's row: status, name, size, and location; a small chip
/// shows whether it's attached to a server.
struct VolumeRow: View {
    let volume: Volume

    var body: some View {
        GlassCard(interactive: true) {
            HStack(spacing: Spacing.unit * 3) {
                Image(systemName: "externaldrive")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(HetzlyColors.textSecondary)

                VStack(alignment: .leading, spacing: Spacing.unit) {
                    Text(volume.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(HetzlyColors.textPrimary)

                    HStack(spacing: Spacing.unit * 2) {
                        GlassChip("\(volume.size) GB")
                        Text("\(flagEmoji(countryCode: volume.location.country)) \(volume.location.city)")
                            .bodySecondary()
                    }
                }

                Spacer(minLength: Spacing.unit * 2)

                if volume.server != nil {
                    Image(systemName: "server.rack")
                        .foregroundStyle(HetzlyColors.statusRunning)
                } else {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(HetzlyColors.textTertiary)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ZStack {
            CanvasBackground()
            VStack(spacing: Spacing.unit * 3) {
                ForEach(ResourcesPreviewFixtures.volumes) { volume in
                    VolumeRow(volume: volume)
                }
            }
            .padding(Spacing.screenMargin)
        }
    }
    .preferredColorScheme(.dark)
}
