import HetznerKit
import SwiftUI

/// Zone detail: record sets grouped by type (A/AAAA/CNAME/MX/TXT/NS/…).
/// Each row shows the monospaced name ("@" for the apex), stacked
/// middle-truncated values, and a TTL chip. Tap to edit, swipe to delete
/// (with confirm), add via the toolbar.
struct DNSZoneDetailView: View {
    let projectID: UUID
    let zoneID: Int
    var initialZone: DNSZone?

    @Environment(AppContainer.self) private var container

    @State private var viewModel: DNSZoneDetailViewModel?
    @State private var isAddingRecord = false
    @State private var editingRecordSet: EditingRecordSet?
    @State private var pendingDeletion: DNSRecordSet?

    init(projectID: UUID, zoneID: Int, initialZone: DNSZone? = nil) {
        self.projectID = projectID
        self.zoneID = zoneID
        self.initialZone = initialZone
    }

    /// Identifiable box for `.sheet(item:)` — a record set's identity is
    /// its name + type.
    private struct EditingRecordSet: Identifiable {
        let recordSet: DNSRecordSet
        var id: String { "\(recordSet.name)|\(recordSet.type.rawValue)" }
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            content
        }
        .navigationTitle(viewModel?.zone?.name ?? initialZone?.name ?? "Zone")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAddingRecord = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add DNS Record")
                .disabled(viewModel?.isSaving == true)
            }
        }
        .task {
            guard viewModel == nil else { return }
            let model = DNSZoneDetailViewModel(
                projectID: projectID,
                zoneID: zoneID,
                container: container,
                initial: initialZone
            )
            viewModel = model
            await model.load()
        }
        .sheet(isPresented: $isAddingRecord) {
            RecordEditSheet(
                existingRecordSet: nil,
                onSave: { name, type, ttl, values in
                    isAddingRecord = false
                    Task { await viewModel?.createRecordSet(name: name, type: type, ttl: ttl, values: values) }
                },
                onCancel: { isAddingRecord = false }
            )
        }
        .sheet(item: $editingRecordSet) { editing in
            RecordEditSheet(
                existingRecordSet: editing.recordSet,
                onSave: { name, type, ttl, values in
                    editingRecordSet = nil
                    Task { await viewModel?.updateRecordSet(name: name, type: type, ttl: ttl, values: values) }
                },
                onCancel: { editingRecordSet = nil }
            )
        }
        .confirmationDialog(
            "Delete Record",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(deletionButtonTitle, role: .destructive) {
                guard let recordSet = pendingDeletion else { return }
                pendingDeletion = nil
                Task { await viewModel?.deleteRecordSet(recordSet) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clients will stop resolving this record once caches expire.")
        }
    }

    private var deletionButtonTitle: String {
        guard let pending = pendingDeletion else { return "Delete Record" }
        return "Delete \(pending.name) \(pending.type.rawValue)"
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let viewModel {
            switch viewModel.loadState {
            case .idle, .loading:
                if viewModel.recordSets.isEmpty { loadingState } else { loadedContent(viewModel) }
            case .failed(let message):
                if viewModel.recordSets.isEmpty { errorState(message) } else { loadedContent(viewModel) }
            case .loaded:
                if viewModel.recordSets.isEmpty {
                    emptyState
                } else {
                    loadedContent(viewModel)
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
            Text("Loading records…").caption()
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

    private var emptyState: some View {
        VStack(spacing: Spacing.unit * 4) {
            if container.settings.mascotEnabled {
                MascotView(state: .peek, scale: 3)
            } else {
                Image(systemName: "tray")
                    .font(.system(size: 40))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
            Text("No records yet. Add the first one to start serving this zone.")
                .bodySecondary()
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.screenMargin * 2)
            PrimaryCTA(title: "Add Record") {
                isAddingRecord = true
            }
        }
    }

    private func loadedContent(_ viewModel: DNSZoneDetailViewModel) -> some View {
        List {
            if viewModel.isSaving {
                HStack(spacing: Spacing.unit * 2) {
                    ProgressView().controlSize(.small).tint(HetzlyColors.textSecondary)
                    Text("Saving…").bodySecondary()
                    if container.settings.mascotEnabled {
                        Spacer()
                        MascotView(state: .work, scale: 1.5)
                    }
                }
                .plainRow()
            }

            if let actionError = viewModel.actionError {
                Text(actionError)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HetzlyColors.destructive)
                    .plainRow()
            }

            ForEach(viewModel.groupedRecordSets, id: \.type.rawValue) { group in
                Section {
                    ForEach(Array(group.sets.enumerated()), id: \.offset) { _, recordSet in
                        Button {
                            guard !viewModel.isSaving else { return }
                            editingRecordSet = EditingRecordSet(recordSet: recordSet)
                        } label: {
                            DNSRecordSetRow(recordSet: recordSet)
                        }
                        .buttonStyle(.plain)
                        .plainRow()
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDeletion = recordSet
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .opacity(viewModel.isSaving ? 0.55 : 1)
                    }
                } header: {
                    SectionLabel(group.type == .unknown ? "Other" : group.type.rawValue)
                        .listRowInsets(EdgeInsets(
                            top: 0, leading: Spacing.screenMargin, bottom: 0, trailing: Spacing.screenMargin
                        ))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await viewModel.load() }
    }
}

/// One record-set row: monospaced name, stacked middle-truncated values,
/// TTL chip.
private struct DNSRecordSetRow: View {
    let recordSet: DNSRecordSet

    var body: some View {
        GlassCard {
            HStack(alignment: .top, spacing: Spacing.unit * 3) {
                VStack(alignment: .leading, spacing: Spacing.unit * 1.5) {
                    Text(recordSet.name)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(HetzlyColors.textPrimary)

                    VStack(alignment: .leading, spacing: Spacing.unit) {
                        ForEach(Array(recordSet.records.enumerated()), id: \.offset) { _, record in
                            Text(RecordValueFormatter.middleTruncated(record.value))
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(HetzlyColors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: Spacing.unit * 2)

                if let ttl = recordSet.ttl {
                    GlassChip(TTLFormatter.compact(ttl), systemImage: "clock")
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        DNSZoneDetailView(
            projectID: UUID(),
            zoneID: DNSPreviewFixtures.zone.id,
            initialZone: DNSPreviewFixtures.zone
        )
        .environment(AppContainer.makeDefault())
    }
    .preferredColorScheme(.dark)
}
