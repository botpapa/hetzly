import HetznerKit
import SwiftUI

/// SSH keys registered on the selected project. Rows show the key name and
/// a middle-truncated monospaced fingerprint; the add flow supports both
/// pasting an existing public key and generating an Ed25519 pair on device.
struct SSHKeysListView: View {
    @Environment(AppContainer.self) private var container
    @Environment(ResourcesProjectSelection.self) private var selection

    @State private var model = ResourceListModel<SSHKey>(load: { [] })
    @State private var isPresentingAdd = false
    @State private var pendingDelete: SSHKey?
    @State private var actionError: String?

    var body: some View {
        ZStack {
            CanvasBackground()
            resourceListBody(
                state: model.state,
                items: model.items,
                emptyTitle: "No SSH Keys",
                emptyMessage: "Add a public key — or generate one right on this device — to log into new servers without passwords.",
                emptyCTA: "Add SSH Key",
                onCreate: { isPresentingAdd = true },
                onRetry: { Task { await model.refresh() } },
                onRefresh: { await model.refresh() }
            ) { key in
                NavigationLink {
                    SSHKeyDetailView(sshKey: key, onChange: { Task { await model.refresh() } })
                } label: {
                    SSHKeyRow(sshKey: key)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        pendingDelete = key
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("SSH Keys")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isPresentingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .task(id: selection.projectID) { await reload() }
        .sheet(isPresented: $isPresentingAdd) {
            SSHKeyAddSheet(projectID: selection.projectID) {
                Task { await model.refresh() }
            }
        }
        .confirmationDialog(
            "Delete SSH Key",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete from Hetzner", role: .destructive) { commitDelete(removePrivateKey: false) }
            if hasStoredPrivateKey(pendingDelete) {
                Button("Delete + remove private key from this device", role: .destructive) {
                    commitDelete(removePrivateKey: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteMessage)
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

    private var deleteMessage: String {
        let base = "This removes \"\(pendingDelete?.name ?? "")\" from Hetzner. Servers that already trust this key keep working."
        if hasStoredPrivateKey(pendingDelete) {
            return base + " A private key for this name is also stored in this device's Keychain."
        }
        return base
    }

    private func hasStoredPrivateKey(_ key: SSHKey?) -> Bool {
        guard let key else { return false }
        return ((try? SSHKeyGenerator.loadPrivateKey(name: key.name)) ?? nil) != nil
    }

    private func reload() async {
        guard let projectID = selection.projectID, let client = container.cloudClient(for: projectID) else {
            model = ResourceListModel(load: { [] })
            return
        }
        model = ResourceListModel(load: { try await client.listSSHKeys() })
        await model.loadIfNeeded()
    }

    private func commitDelete(removePrivateKey: Bool) {
        guard let key = pendingDelete else { return }
        pendingDelete = nil
        guard let projectID = selection.projectID, let client = container.cloudClient(for: projectID) else { return }
        Task {
            let error = await confirmDestructive(
                container: container,
                reason: "Confirm deleting SSH key \"\(key.name)\""
            ) {
                try await client.deleteSSHKey(id: key.id)
                if removePrivateKey {
                    try SSHKeyGenerator.deletePrivateKey(name: key.name)
                }
            }
            if let error {
                actionError = error
            } else {
                await model.refresh()
            }
        }
    }
}

struct SSHKeyRow: View {
    let sshKey: SSHKey

    var body: some View {
        GlassCard(interactive: true) {
            HStack(spacing: Spacing.unit * 3) {
                Image(systemName: "key")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(HetzlyColors.textSecondary)

                VStack(alignment: .leading, spacing: Spacing.unit) {
                    Text(sshKey.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(HetzlyColors.textPrimary)
                    Text(ResourceFormatting.truncatedMiddle(sshKey.fingerprint, keep: 12))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(HetzlyColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: Spacing.unit * 2)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ZStack {
            CanvasBackground()
            VStack(spacing: Spacing.unit * 3) {
                ForEach(ResourcesPreviewFixtures.sshKeys) { key in
                    SSHKeyRow(sshKey: key)
                }
            }
            .padding(Spacing.screenMargin)
        }
    }
    .preferredColorScheme(.dark)
}
