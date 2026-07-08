import HetznerKit
import SwiftUI

/// Create-certificate sheet, two modes:
///
/// - **Managed**: name + domain list; Hetzner issues and renews via Let's
///   Encrypt.
/// - **Upload**: name + certificate PEM + private key PEM. The private key
///   is redacted while typing (`.privacySensitive`), used only to build the
///   request, and never retained after the call returns.
struct CertificateCreateSheet: View {
    let projectID: UUID?
    let onCreated: () -> Void

    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case managed = "Managed"
        case upload = "Upload"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .managed
    @State private var name = ""
    @State private var domainsText = ""
    @State private var certificatePEM = ""
    @State private var privateKeyPEM = ""
    @State private var isPrivateKeyRevealed = false

    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var domains: [String] {
        domainsText
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var canSubmit: Bool {
        guard !trimmedName.isEmpty, !isSubmitting else { return false }
        switch mode {
        case .managed:
            return !domains.isEmpty
        case .upload:
            return certificatePEM.contains("BEGIN CERTIFICATE") && privateKeyPEM.contains("PRIVATE KEY")
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()
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

                        nameSection

                        switch mode {
                        case .managed:
                            domainsSection
                        case .upload:
                            uploadSection
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(HetzlyColors.destructive)
                        }

                        PrimaryCTA(title: submitTitle, action: submit)
                            .frame(maxWidth: .infinity)
                            .disabled(!canSubmit)
                    }
                    .padding(Spacing.screenMargin)
                }
            }
            .navigationTitle("New Certificate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSubmitting)
                }
            }
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    private var submitTitle: String {
        if isSubmitting { return mode == .managed ? "Requesting…" : "Uploading…" }
        return mode == .managed ? "Request Certificate" : "Upload Certificate"
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Name")
            GlassCard {
                TextField("e.g. example-com", text: $name)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }

    private var domainsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Domains")
            GlassCard {
                TextEditor(text: $domainsText)
                    .frame(minHeight: 90)
                    .font(.system(size: 15, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }
            Text("One domain per line (or comma-separated), e.g. example.com, www.example.com. DNS must already point at a Hetzner load balancer for issuance to succeed.")
                .caption()
        }
    }

    private var uploadSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 5) {
            VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                SectionLabel("Certificate (PEM)")
                GlassCard {
                    TextEditor(text: $certificatePEM)
                        .frame(minHeight: 110)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Text("Paste the full chain, starting with -----BEGIN CERTIFICATE-----.")
                    .caption()
            }

            VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                HStack {
                    SectionLabel("Private Key (PEM)")
                    Spacer()
                    Button {
                        isPrivateKeyRevealed.toggle()
                    } label: {
                        Image(systemName: isPrivateKeyRevealed ? "eye.slash" : "eye")
                            .foregroundStyle(HetzlyColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPrivateKeyRevealed ? "Hide private key" : "Reveal private key")
                }
                GlassCard {
                    TextEditor(text: $privateKeyPEM)
                        .frame(minHeight: 110)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .blur(radius: isPrivateKeyRevealed || privateKeyPEM.isEmpty ? 0 : 5)
                        .privacySensitive()
                }
                Text("Sent to Hetzner once to create the certificate — never stored on this device.")
                    .caption()
            }
        }
    }

    private func submit() {
        guard canSubmit, let projectID, let client = container.cloudClient(for: projectID) else { return }
        errorMessage = nil
        isSubmitting = true
        let name = trimmedName
        let mode = mode
        let domains = domains
        let certificatePEM = certificatePEM
        let privateKeyPEM = privateKeyPEM

        Task {
            defer { isSubmitting = false }
            do {
                switch mode {
                case .managed:
                    _ = try await client.createManagedCertificate(name: name, domainNames: domains)
                case .upload:
                    _ = try await client.uploadCertificate(name: name, certificate: certificatePEM, privateKey: privateKeyPEM)
                }
                onCreated()
                dismiss()
            } catch {
                errorMessage = resourceUserMessage(for: error)
            }
        }
    }
}

#Preview {
    CertificateCreateSheet(projectID: nil, onCreated: {})
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}
