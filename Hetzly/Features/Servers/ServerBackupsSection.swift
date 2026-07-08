import HetznerKit
import SwiftUI

/// BACKUPS & SNAPSHOTS section: backups status/toggle row, "Create
/// Snapshot", and the list of snapshots created from this server
/// (description, size, age; delete with confirm; tap → rebuild-from-image
/// shortcut).
///
/// Deviation from the "swipe delete" brief: the detail screen is a
/// `ScrollView`, not a `List`, and `.swipeActions` only works inside `List`
/// rows — so deletion is an explicit trash button per row feeding the same
/// confirm flow instead of forking the screen into a mixed List layout.
struct ServerBackupsSection: View {
    let server: Server
    let snapshots: [HetznerKit.Image]
    let snapshotsState: ServerDetailViewModel.LoadState
    var onToggleBackups: () -> Void
    var onCreateSnapshot: () -> Void
    var onDeleteSnapshot: (HetznerKit.Image) -> Void
    var onRebuildFromSnapshot: (HetznerKit.Image) -> Void

    @State private var pendingDeletion: HetznerKit.Image?

    private var backupsEnabled: Bool { server.backupWindow != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            SectionLabel("Backups & Snapshots")

            GlassCard {
                VStack(spacing: 0) {
                    backupsRow
                    divider
                    createSnapshotRow
                    snapshotRows
                }
            }
        }
        .confirmationDialog(
            "Delete Snapshot",
            isPresented: pendingDeletionBinding,
            titleVisibility: .visible
        ) {
            Button("Delete \"\(pendingDeletion?.description ?? "snapshot")\"", role: .destructive) {
                if let image = pendingDeletion {
                    onDeleteSnapshot(image)
                }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("This permanently deletes the snapshot. It cannot be restored afterwards.")
        }
    }

    private var divider: some View {
        Divider().overlay(HetzlyColors.textTertiary.opacity(0.2))
    }

    private var backupsRow: some View {
        HStack(spacing: Spacing.unit * 3) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(backupsEnabled ? HetzlyColors.statusRunning : HetzlyColors.textTertiary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Automatic Backups")
                    .bodyPrimary()
                Text(backupsEnabled ? "On · window \(server.backupWindow ?? "")h UTC" : "Off")
                    .caption()
            }
            Spacer()
            Toggle("Automatic Backups", isOn: toggleBinding)
                .labelsHidden()
                .tint(HetzlyColors.accent)
        }
        .padding(.vertical, Spacing.unit * 2)
    }

    /// The toggle never flips optimistically — it always reflects the
    /// server's reported state, and flipping it just kicks off the
    /// confirm-then-track flow owned by the caller.
    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { backupsEnabled },
            set: { _ in onToggleBackups() }
        )
    }

    private var createSnapshotRow: some View {
        Button(action: onCreateSnapshot) {
            HStack(spacing: Spacing.unit * 3) {
                Image(systemName: "camera")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(HetzlyColors.accent)
                    .frame(width: 28)
                Text("Create Snapshot")
                    .bodyPrimary()
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
            .padding(.vertical, Spacing.unit * 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var snapshotRows: some View {
        switch snapshotsState {
        case .loading where snapshots.isEmpty:
            divider
            HStack(spacing: Spacing.unit * 2) {
                ProgressView()
                Text("Loading snapshots…").caption()
            }
            .padding(.vertical, Spacing.unit * 3)
        case .failed(let message):
            divider
            Text(message)
                .caption()
                .padding(.vertical, Spacing.unit * 3)
        default:
            if snapshots.isEmpty {
                divider
                Text("No snapshots of this server yet.")
                    .caption()
                    .padding(.vertical, Spacing.unit * 3)
            } else {
                ForEach(snapshots) { snapshot in
                    divider
                    snapshotRow(snapshot)
                }
            }
        }
    }

    private func snapshotRow(_ snapshot: HetznerKit.Image) -> some View {
        HStack(spacing: Spacing.unit * 3) {
            Button {
                onRebuildFromSnapshot(snapshot)
            } label: {
                HStack(spacing: Spacing.unit * 3) {
                    Image(systemName: "camera.on.rectangle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(HetzlyColors.textSecondary)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.description)
                            .bodySecondary()
                            .foregroundStyle(HetzlyColors.textPrimary)
                            .lineLimit(1)
                        Text(snapshotDetail(snapshot))
                            .caption()
                            .monospacedDigit()
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Rebuild the server from this snapshot")

            Button {
                pendingDeletion = snapshot
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(HetzlyColors.destructive)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete snapshot \(snapshot.description)")
        }
        .padding(.vertical, Spacing.unit * 2)
    }

    private func snapshotDetail(_ snapshot: HetznerKit.Image) -> String {
        var parts: [String] = []
        if let size = snapshot.imageSize {
            parts.append(ServerDetailSupport.gigabytes(size))
        }
        parts.append(snapshot.created.formatted(date: .abbreviated, time: .omitted))
        if snapshot.status == .creating {
            parts.append("creating…")
        }
        return parts.joined(separator: " · ")
    }

    private var pendingDeletionBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        ScrollView {
            ServerBackupsSection(
                server: PreviewFixtures.server,
                snapshots: [PreviewFixtures.snapshot],
                snapshotsState: .loaded,
                onToggleBackups: {},
                onCreateSnapshot: {},
                onDeleteSnapshot: { _ in },
                onRebuildFromSnapshot: { _ in }
            )
            .padding(Spacing.screenMargin)
        }
    }
    .preferredColorScheme(.dark)
}
