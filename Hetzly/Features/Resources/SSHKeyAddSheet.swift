import HetznerKit
import SwiftUI

/// Two-mode add-key flow:
///
/// - **Paste public key**: name + a public-key `TextEditor` with a
///   client-side "starts with `ssh-`" sanity check, uploaded via
///   `createSSHKey`.
/// - **Generate on device**: name only. `SSHKeyGenerator.generateEd25519`
///   creates the pair locally, the public half is uploaded, the private half
///   is saved to this device's Keychain — then a one-time REVEAL screen
///   shows the private key (sensitive card, 60s-expiring copy) until the
///   user confirms they saved it. The private key never leaves the device
///   except via that user-initiated copy.
struct SSHKeyAddSheet: View {
    let projectID: UUID?
    let onCreated: () -> Void

    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case paste = "Paste public key"
        case generate = "Generate on device"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .paste
    @State private var name = ""
    @State private var publicKeyText = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    /// Set once a generated key was uploaded + stored — switches the sheet
    /// to the reveal screen. The sheet can't be dismissed from there except
    /// through "I saved it".
    @State private var revealedKey: GeneratedSSHKey?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPublicKey: String {
        publicKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var publicKeyLooksValid: Bool {
        trimmedPublicKey.hasPrefix("ssh-")
    }

    private var canSubmit: Bool {
        guard !trimmedName.isEmpty, !isSubmitting else { return false }
        switch mode {
        case .paste: return publicKeyLooksValid
        case .generate: return true
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()
                if let revealedKey {
                    SSHKeyRevealView(keyName: trimmedName, generated: revealedKey) {
                        onCreated()
                        dismiss()
                    }
                } else {
                    form
                }
            }
            .navigationTitle(revealedKey == nil ? "Add SSH Key" : "Save Your Private Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if revealedKey == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.disabled(isSubmitting)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isSubmitting || revealedKey != nil)
    }

    // MARK: - Form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.unit * 7) {
                GlassCard {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                    SectionLabel("Name")
                    GlassCard {
                        TextField("e.g. MacBook Pro", text: $name)
                            .textFieldStyle(.plain)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }
                }

                switch mode {
                case .paste:
                    pasteSection
                case .generate:
                    generateExplainer
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(HetzlyColors.destructive)
                }

                PrimaryCTA(
                    title: submitTitle,
                    action: submit
                )
                .frame(maxWidth: .infinity)
                .disabled(!canSubmit)
            }
            .padding(Spacing.screenMargin)
        }
    }

    private var submitTitle: String {
        if isSubmitting { return mode == .generate ? "Generating…" : "Adding…" }
        return mode == .generate ? "Generate & Upload" : "Add Key"
    }

    private var pasteSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Public Key")
            GlassCard {
                TextEditor(text: $publicKeyText)
                    .frame(minHeight: 120)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            if !trimmedPublicKey.isEmpty && !publicKeyLooksValid {
                Text("That doesn't look like an OpenSSH public key — it should start with \"ssh-\".")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HetzlyColors.destructive)
            }
            Text("Paste the contents of your .pub file, e.g. \"ssh-ed25519 AAAA… user@host\".")
                .caption()
        }
    }

    private var generateExplainer: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                Label("Generated on this device", systemImage: "iphone.and.arrow.forward")
                    .bodyPrimary()
                Text(
                    "Hetzly creates a modern Ed25519 key pair locally. The public key is uploaded to Hetzner; "
                        + "the private key is stored only in this device's Keychain and shown once so you can save it."
                )
                .bodySecondary()
            }
        }
    }

    // MARK: - Submit

    private func submit() {
        guard canSubmit, let projectID, let client = container.cloudClient(for: projectID) else { return }
        errorMessage = nil
        isSubmitting = true
        let name = trimmedName
        let mode = mode
        let publicKey = trimmedPublicKey

        Task {
            defer { isSubmitting = false }
            do {
                switch mode {
                case .paste:
                    _ = try await client.createSSHKey(name: name, publicKey: publicKey)
                    onCreated()
                    dismiss()
                case .generate:
                    let generated = SSHKeyGenerator.generateEd25519(comment: name)
                    _ = try await client.createSSHKey(name: name, publicKey: generated.publicKeyOpenSSH)
                    try SSHKeyGenerator.savePrivateKey(generated, name: name)
                    revealedKey = generated
                }
            } catch {
                errorMessage = resourceUserMessage(for: error)
            }
        }
    }
}

/// The one-time private-key reveal: a sensitive glass card with the PEM in
/// monospace, copy-with-60s-expiry via `SensitivePasteboard`, and an
/// "I saved it" confirmation. Also explains that the private key stays in
/// this device's Keychain and can be re-exported from the key's detail
/// screen later.
struct SSHKeyRevealView: View {
    let keyName: String
    let generated: GeneratedSSHKey
    let onConfirm: () -> Void

    @State private var didCopy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.unit * 5) {
                Label("This is your private key", systemImage: "exclamationmark.shield")
                    .bodyPrimary()
                    .fontWeight(.semibold)

                Text(
                    "It's stored in this device's Keychain under \"\(keyName)\" and can be re-exported later "
                        + "from the key's detail screen (Face ID required). Anyone with this key can log into your servers — "
                        + "keep it secret."
                )
                .bodySecondary()

                GlassCard {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(generated.privateKeyOpenSSH)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(HetzlyColors.textPrimary)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 240)
                }
                .privacySensitive()

                VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                    Button {
                        SensitivePasteboard.copy(generated.privateKeyOpenSSH)
                        didCopy = true
                    } label: {
                        Label(didCopy ? "Copied — clears in 60s" : "Copy private key", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .secondaryCTAStyle()

                    Text("The clipboard copy stays on this device and expires after 60 seconds.")
                        .caption()
                }

                DetailInfoRow(
                    label: "Fingerprint",
                    value: ResourceFormatting.truncatedMiddle(generated.fingerprintSHA256, keep: 12),
                    monospaced: true
                )

                PrimaryCTA(title: "I saved it", action: onConfirm)
                    .frame(maxWidth: .infinity)
            }
            .padding(Spacing.screenMargin)
        }
    }
}

#Preview {
    SSHKeyAddSheet(projectID: nil, onCreated: {})
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}

#Preview("Reveal") {
    ZStack {
        CanvasBackground()
        SSHKeyRevealView(
            keyName: "MacBook Pro",
            generated: SSHKeyGenerator.generateEd25519(comment: "preview@hetzly"),
            onConfirm: {}
        )
    }
    .preferredColorScheme(.dark)
}
