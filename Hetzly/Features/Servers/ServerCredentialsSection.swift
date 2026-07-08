import SwiftUI

/// CREDENTIALS section (Control tab): the durably-saved root password for
/// this server, if `ServerCredentialsVault` has one — from a prior
/// reset-root-password or enable-rescue-mode result (see
/// `ServerDetailViewModel.performManagement`, which saves both). Reveal is
/// unconditionally Face ID/Touch ID gated, mirroring
/// `SSHKeyDetailView.exportPrivateKey`'s "always gate secret reveal
/// regardless of the destructive-actions setting" convention.
///
/// Deliberately reads `ServerCredentialsVault` directly in `body` rather
/// than caching presence into `@State`: the vault is a cheap
/// Keychain/UserDefaults read, and re-deriving it fresh on every render
/// means a reset-root-password/enable-rescue success (which re-renders
/// `ServerDetailView`) or this section's own Delete button immediately
/// reflects the current on-device state with no extra plumbing.
struct ServerCredentialsSection: View {
    let serverID: Int

    @Environment(AppContainer.self) private var container

    @State private var isAuthenticating = false
    @State private var authError: String?
    @State private var revealedPassword: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            SectionLabel("Credentials")

            if let savedPassword = ServerCredentialsVault.rootPassword(serverID: serverID) {
                if let revealedPassword {
                    SensitiveSecretCard(
                        title: "Root Password",
                        secret: revealedPassword,
                        note: "Saved on this device from a previous reset or rescue-mode enable. Hetzner does not store this password."
                    )
                    Button(role: .destructive) {
                        delete()
                    } label: {
                        Label("Delete Saved Password", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .secondaryCTAStyle()
                } else {
                    lockedCard(savedPassword: savedPassword)
                }
            } else {
                GlassCard {
                    HStack(spacing: Spacing.unit * 3) {
                        Image(systemName: "key.slash")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(HetzlyColors.textTertiary)
                            .frame(width: 28)
                        Text("No saved password for this server. Resetting the root password or enabling rescue mode saves one here.")
                            .caption()
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func lockedCard(savedPassword: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                HStack(spacing: Spacing.unit * 3) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(HetzlyColors.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Root Password Saved")
                            .bodyPrimary()
                        Text("Saved on this device from a previous reset or rescue-mode enable.")
                            .caption()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                if let authError {
                    Text(authError)
                        .caption()
                        .foregroundStyle(HetzlyColors.destructive)
                }

                Button {
                    reveal()
                } label: {
                    Label(isAuthenticating ? "Verifying…" : "Reveal with Face ID", systemImage: "faceid")
                        .frame(maxWidth: .infinity)
                }
                .secondaryCTAStyle()
                .disabled(isAuthenticating)
            }
        }
    }

    /// Biometric gate is unconditional here (unlike destructive power/
    /// management actions, which respect the Settings toggle) — revealing a
    /// saved root password is always worth a Face ID check.
    private func reveal() {
        guard !isAuthenticating else { return }
        authError = nil
        isAuthenticating = true
        Task {
            defer { isAuthenticating = false }
            let approved = await container.biometricGate.authenticate(
                reason: "Reveal the saved root password for this server"
            )
            guard approved else {
                authError = container.biometricGate.lastErrorMessage ?? "Authentication failed. Try again."
                return
            }
            revealedPassword = ServerCredentialsVault.rootPassword(serverID: serverID)
        }
    }

    private func delete() {
        ServerCredentialsVault.deleteRootPassword(serverID: serverID)
        revealedPassword = nil
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        ScrollView {
            ServerCredentialsSection(serverID: PreviewFixtures.server.id)
                .padding(Spacing.screenMargin)
        }
    }
    .environment(AppContainer.makeDefault())
    .preferredColorScheme(.dark)
}
