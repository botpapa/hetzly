import HetznerKit
import SwiftUI

/// Placement groups for the selected project — spread groups keep servers on
/// separate physical hosts for fault isolation.
struct PlacementGroupsListView: View {
    @Environment(AppContainer.self) private var container
    @Environment(ResourcesProjectSelection.self) private var selection

    @State private var model = ResourceListModel<PlacementGroup>(load: { [] })
    @State private var isPresentingCreate = false
    @State private var pendingDelete: PlacementGroup?
    @State private var actionError: String?

    var body: some View {
        ZStack {
            CanvasBackground()
            resourceListBody(
                state: model.state,
                items: model.items,
                emptyTitle: "No Placement Groups",
                emptyMessage: "Spread placement groups keep servers on separate physical hosts, so one host failure can't take them all down.",
                emptyCTA: "Create Placement Group",
                onCreate: { isPresentingCreate = true },
                onRetry: { Task { await model.refresh() } },
                onRefresh: { await model.refresh() }
            ) { group in
                PlacementGroupRow(group: group)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDelete = group
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .navigationTitle("Placement Groups")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isPresentingCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .task(id: selection.projectID) { await reload() }
        .sheet(isPresented: $isPresentingCreate) {
            PlacementGroupCreateSheet(projectID: selection.projectID) {
                Task { await model.refresh() }
            }
        }
        .confirmationDialog(
            "Delete Placement Group",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { commitDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes \"\(pendingDelete?.name ?? "")\". Servers in the group are not affected.")
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
        model = ResourceListModel(load: { try await client.listPlacementGroups() })
        await model.loadIfNeeded()
    }

    private func commitDelete() {
        guard let group = pendingDelete else { return }
        pendingDelete = nil
        guard let projectID = selection.projectID, let client = container.cloudClient(for: projectID) else { return }
        Task {
            let error = await confirmDestructive(
                container: container,
                reason: "Confirm deleting placement group \"\(group.name)\""
            ) {
                try await client.deletePlacementGroup(id: group.id)
            }
            if let error {
                actionError = error
            } else {
                await model.refresh()
            }
        }
    }
}

struct PlacementGroupRow: View {
    let group: PlacementGroup

    var body: some View {
        GlassCard(interactive: true) {
            HStack(spacing: Spacing.unit * 3) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(HetzlyColors.textSecondary)

                VStack(alignment: .leading, spacing: Spacing.unit) {
                    Text(group.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(HetzlyColors.textPrimary)
                    Text(group.type == .spread ? "Spread" : "Unknown type")
                        .bodySecondary()
                }

                Spacer(minLength: Spacing.unit * 2)

                GlassChip("\(group.servers.count)", systemImage: "server.rack")
            }
        }
    }
}

/// Create sheet: name + type. Hetzner currently only offers `spread`, shown
/// as a single locked option so the UI is honest about the choice space.
struct PlacementGroupCreateSheet: View {
    let projectID: UUID?
    let onCreated: () -> Void

    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedName.isEmpty && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.unit * 7) {
                        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                            SectionLabel("Name")
                            GlassCard {
                                TextField("e.g. prod-spread", text: $name)
                                    .textFieldStyle(.plain)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                        }

                        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                            SectionLabel("Type")
                            GlassCard {
                                HStack {
                                    Label("Spread", systemImage: "square.stack.3d.up")
                                        .foregroundStyle(HetzlyColors.textPrimary)
                                    Spacer()
                                    GlassChip("Only option")
                                }
                            }
                            Text("Servers in a spread group run on separate physical hosts.")
                                .caption()
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(HetzlyColors.destructive)
                        }

                        PrimaryCTA(title: isSubmitting ? "Creating…" : "Create Placement Group", action: submit)
                            .frame(maxWidth: .infinity)
                            .disabled(!canSubmit)
                    }
                    .padding(Spacing.screenMargin)
                }
            }
            .navigationTitle("New Placement Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSubmitting)
                }
            }
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    private func submit() {
        guard canSubmit, let projectID, let client = container.cloudClient(for: projectID) else { return }
        errorMessage = nil
        isSubmitting = true
        let name = trimmedName

        Task {
            defer { isSubmitting = false }
            do {
                _ = try await client.createPlacementGroup(name: name, type: .spread)
                onCreated()
                dismiss()
            } catch {
                errorMessage = resourceUserMessage(for: error)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ZStack {
            CanvasBackground()
            VStack(spacing: Spacing.unit * 3) {
                ForEach(ResourcesPreviewFixtures.placementGroups) { group in
                    PlacementGroupRow(group: group)
                }
            }
            .padding(Spacing.screenMargin)
        }
    }
    .preferredColorScheme(.dark)
}
