import HetznerKit
import SwiftUI

/// SSH key detail: full copyable public key, fingerprint, created date. If a
/// private key generated on this device exists in the Keychain under this
/// key's name, an "Export private key" action appears — ALWAYS behind
/// `BiometricGate.authenticate`, regardless of the destructive-actions
/// setting. Deleting also offers to remove the stored private key.
struct SSHKeyDetailView: View {
    let sshKey: SSHKey
    var onChange: () -> Void = {}

    @Environment(AppContainer.self) private var container
    @Environment(ResourcesProjectSelection.self) private var selection
    @Environment(\.dismiss) private var dismiss

    @State private var hasStoredPrivateKey = false
    @State private var exportedPrivateKey: String?
    @State private var didCopyPublic = false
    @State private var didCopyPrivate = false
    @State private var actionError: String?
    @State private var isPresentingDeleteConfirm = false
    @State private var isAuthenticating = false

    private var client: CloudClient? {
        selection.projectID.flatMap { container.cloudClient(for: $0) }
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.unit * 6) {
                    summaryCard
                    publicKeySection

                    if let actionError {
                        ResourceErrorBanner(message: actionError)
                    }

                    if hasStoredPrivateKey {
                        privateKeySection
                    }

                    dangerZone
                }
                .padding(Spacing.screenMargin)
            }
        }
        .navigationTitle(sshKey.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshPrivateKeyPresence() }
        .onDisappear { exportedPrivateKey = nil }
        .confirmationDialog(
            "Delete SSH Key",
            isPresented: $isPresentingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete from Hetzner", role: .destructive) { commitDelete(removePrivateKey: false) }
            if hasStoredPrivateKey {
                Button("Delete + remove private key from this device", role: .destructive) {
                    commitDelete(removePrivateKey: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
    }

    private var deleteMessage: String {
        let base = "This removes \"\(sshKey.name)\" from Hetzner. Servers that already trust this key keep working."
        if hasStoredPrivateKey {
            return base + " A private key for this name is also stored in this device's Keychain."
        }
        return base
    }

    // MARK: - Summary

    private var summaryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                DetailInfoRow(
                    label: "Fingerprint",
                    value: ResourceFormatting.truncatedMiddle(sshKey.fingerprint, keep: 14),
                    monospaced: true
                )
                DetailInfoRow(label: "Created", value: ResourceFormatting.dateString(sshKey.created))
                if hasStoredPrivateKey {
                    HStack(spacing: Spacing.unit * 2) {
                        Image(systemName: "checkmark.shield")
                            .foregroundStyle(HetzlyColors.statusRunning)
                        Text("Private key stored in this device's Keychain.").caption()
                    }
                }
            }
        }
    }

    // MARK: - Public key

    private var publicKeySection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            SectionLabel("Public Key")
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(sshKey.publicKey)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(HetzlyColors.textPrimary)
                            .textSelection(.enabled)
                    }

                    Button {
                        UIPasteboard.general.string = sshKey.publicKey
                        didCopyPublic = true
                    } label: {
                        Label(didCopyPublic ? "Copied" : "Copy public key", systemImage: "doc.on.doc")
                    }
                    .secondaryCTAStyle()
                }
            }
        }
    }

    // MARK: - Private key export

    private var privateKeySection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            SectionLabel("Private Key")
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                    if let exportedPrivateKey {
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(exportedPrivateKey)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(HetzlyColors.textPrimary)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 220)
                        .privacySensitive()

                        Button {
                            SensitivePasteboard.copy(exportedPrivateKey)
                            didCopyPrivate = true
                        } label: {
                            Label(didCopyPrivate ? "Copied — clears in 60s" : "Copy private key", systemImage: "doc.on.doc")
                        }
                        .secondaryCTAStyle()

                        Button("Hide") {
                            self.exportedPrivateKey = nil
                            didCopyPrivate = false
                        }
                        .secondaryCTAStyle()
                    } else {
                        Text("The private key generated on this device can be re-exported with Face ID.")
                            .bodySecondary()
                        Button {
                            exportPrivateKey()
                        } label: {
                            Label(isAuthenticating ? "Verifying…" : "Export private key", systemImage: "faceid")
                        }
                        .secondaryCTAStyle()
                        .disabled(isAuthenticating)
                    }
                }
            }
        }
    }

    // MARK: - Danger zone

    private var dangerZone: some View {
        DisclosureGroup {
            GlassCard {
                Button(role: .destructive) {
                    isPresentingDeleteConfirm = true
                } label: {
                    HStack {
                        Label("Delete SSH Key", systemImage: "trash")
                            .foregroundStyle(HetzlyColors.destructive)
                        Spacer()
                    }
                    .padding(.vertical, Spacing.unit * 2)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, Spacing.unit * 3)
        } label: {
            Text("Danger Zone")
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(HetzlyColors.textTertiary)
        }
        .tint(HetzlyColors.textTertiary)
    }

    // MARK: - Actions

    private func refreshPrivateKeyPresence() {
        hasStoredPrivateKey = ((try? SSHKeyGenerator.loadPrivateKey(name: sshKey.name)) ?? nil) != nil
    }

    /// Biometric gate is unconditional here (unlike destructive actions,
    /// which respect the Settings toggle): exporting a private key is always
    /// worth a Face ID check.
    private func exportPrivateKey() {
        guard !isAuthenticating else { return }
        actionError = nil
        isAuthenticating = true
        Task {
            defer { isAuthenticating = false }
            let approved = await container.biometricGate.authenticate(
                reason: "Export the private key for \"\(sshKey.name)\""
            )
            guard approved else {
                actionError = container.biometricGate.lastErrorMessage ?? "Authentication failed. Try again."
                return
            }
            do {
                guard let key = try SSHKeyGenerator.loadPrivateKey(name: sshKey.name) else {
                    hasStoredPrivateKey = false
                    actionError = "No private key found in the Keychain for this name."
                    return
                }
                exportedPrivateKey = key
            } catch {
                actionError = "Couldn't read the private key from the Keychain."
            }
        }
    }

    private func commitDelete(removePrivateKey: Bool) {
        guard let client else { return }
        Task {
            let error = await confirmDestructive(
                container: container,
                reason: "Confirm deleting SSH key \"\(sshKey.name)\""
            ) {
                try await client.deleteSSHKey(id: sshKey.id)
                if removePrivateKey {
                    try SSHKeyGenerator.deletePrivateKey(name: sshKey.name)
                }
            }
            if let error {
                actionError = error
            } else {
                onChange()
                dismiss()
            }
        }
    }
}

#Preview {
    NavigationStack {
        SSHKeyDetailView(sshKey: ResourcesPreviewFixtures.sshKeys[0])
            .environment(AppContainer.makeDefault())
            .environment(ResourcesProjectSelection())
    }
    .preferredColorScheme(.dark)
}
