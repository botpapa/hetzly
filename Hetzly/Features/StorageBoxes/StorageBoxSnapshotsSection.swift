import HetznerKit
import SwiftUI

/// SNAPSHOTS section on Storage Box Detail: list with created date and
/// size, a "Create Snapshot" affordance (opens `StorageBoxCreateSnapshotSheet`), and
/// per-row delete (confirmed by the caller — see
/// `StorageBoxDetailView.confirmDeleteSnapshot`).
struct StorageBoxSnapshotsSection: View {
    let snapshots: [StorageBoxSnapshot]
    var supported: Bool = true
    var isPerformingAction: Bool = false
    var onCreateTapped: () -> Void = {}
    var onDeleteTapped: (StorageBoxSnapshot) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            HStack {
                SectionLabel("Snapshots")
                Spacer()
                if supported {
                    Button { onCreateTapped() } label: { Image(systemName: "plus.circle") }
                        .accessibilityLabel("Create Snapshot")
                        .disabled(isPerformingAction)
                }
            }

            if !supported {
                GlassCard {
                    Text("Snapshots aren't supported by this version of Hetzly yet.")
                        .caption()
                }
            } else if snapshots.isEmpty {
                GlassCard { Text("No snapshots yet.").bodySecondary() }
            } else {
                ForEach(snapshots) { snapshot in
                    GlassCard {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: Spacing.unit) {
                                Text(snapshot.name)
                                    .hetzlyMonoNumbers()
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundStyle(HetzlyColors.textPrimary)
                                if !snapshot.description.isEmpty {
                                    Text(snapshot.description).bodySecondary()
                                }
                                HStack(spacing: Spacing.unit * 2) {
                                    Text(StorageBoxSupport.dateTimeString(snapshot.created)).caption()
                                    Text("·").caption()
                                    Text(StorageBoxSupport.bytes(snapshot.stats.size)).caption()
                                    if snapshot.isAutomatic {
                                        Text("·").caption()
                                        Text("Automatic").caption()
                                    }
                                }
                            }
                            Spacer()
                            Button(role: .destructive) {
                                onDeleteTapped(snapshot)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Delete Snapshot \(snapshot.name)")
                            .disabled(isPerformingAction)
                        }
                    }
                }
            }
        }
    }
}

/// Sheet for creating a manual snapshot. Storage Box snapshot names are
/// server-assigned (a timestamp) — only an optional description is
/// user-settable at creation time, mirroring the Cloud API's
/// `createImage(serverID:description:)` convention.
struct StorageBoxCreateSnapshotSheet: View {
    let onCreate: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            Text("Create Snapshot").bodyPrimary().fontWeight(.semibold)
            Text("Snapshots are named automatically; add an optional description to help you find this one later.")
                .caption()

            GlassCard {
                TextField("Description (optional)", text: $description)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
            }

            Spacer(minLength: 0)

            HStack(spacing: Spacing.unit * 3) {
                Button("Cancel") { dismiss() }.secondaryCTAStyle().frame(maxWidth: .infinity)
                PrimaryCTA(title: isSubmitting ? "Creating…" : "Create") {
                    isSubmitting = true
                    let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
                    onCreate(trimmed.isEmpty ? nil : trimmed)
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .disabled(isSubmitting)
            }
        }
        .padding(Spacing.screenMargin)
        .padding(.top, Spacing.unit * 2)
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
        .presentationBackground { CanvasBackground() }
        .presentationCornerRadius(Radius.card)
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        ScrollView {
            StorageBoxSnapshotsSection(snapshots: StorageBoxPreviewFixtures.snapshots)
                .padding(Spacing.screenMargin)
        }
    }
    .preferredColorScheme(.dark)
}
