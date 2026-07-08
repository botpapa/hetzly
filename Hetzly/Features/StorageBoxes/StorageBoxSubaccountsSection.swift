import HetznerKit
import SwiftUI

/// SUBACCOUNTS section on Storage Box Detail: list with username and
/// description, a "Create Subaccount" affordance (opens
/// `CreateSubaccountSheet`), and per-row delete (confirmed by the caller —
/// see `StorageBoxDetailView.confirmDeleteSubaccount`).
struct StorageBoxSubaccountsSection: View {
    let subaccounts: [StorageBoxSubaccount]
    var supported: Bool = true
    var isPerformingAction: Bool = false
    var onCreateTapped: () -> Void = {}
    var onDeleteTapped: (StorageBoxSubaccount) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            HStack {
                SectionLabel("Subaccounts")
                Spacer()
                if supported {
                    Button { onCreateTapped() } label: { Image(systemName: "plus.circle") }
                        .accessibilityLabel("Create Subaccount")
                        .disabled(isPerformingAction)
                }
            }

            if !supported {
                GlassCard {
                    Text("Subaccounts aren't supported by this version of Hetzly yet.")
                        .caption()
                }
            } else if subaccounts.isEmpty {
                GlassCard { Text("No subaccounts yet.").bodySecondary() }
            } else {
                ForEach(subaccounts) { subaccount in
                    GlassCard {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: Spacing.unit) {
                                Text(subaccount.username)
                                    .hetzlyMonoNumbers()
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundStyle(HetzlyColors.textPrimary)
                                if !subaccount.description.isEmpty {
                                    Text(subaccount.description).bodySecondary()
                                }
                                Text(subaccount.homeDirectory).caption()
                            }
                            Spacer()
                            Button(role: .destructive) {
                                onDeleteTapped(subaccount)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Delete Subaccount \(subaccount.username)")
                            .disabled(isPerformingAction)
                        }
                    }
                }
            }
        }
    }
}

/// Sheet for creating a subaccount: home directory (required, relative to
/// the Storage Box's root), an optional name/description, and its own
/// access settings (subaccounts can be scoped more tightly than the parent
/// box). The subaccount's login password isn't collected here — Hetzner
/// requires the caller to supply one, so `StorageBoxDetailViewModel`
/// generates a strong one and reveals it once creation succeeds, matching
/// the reset-password flow's "shown once" treatment.
struct CreateSubaccountSheet: View {
    let onCreate: (String, String?, String?, StorageBoxSubaccountAccessSettings) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var homeDirectory = ""
    @State private var name = ""
    @State private var description = ""
    @State private var reachableExternally = true
    @State private var sambaEnabled = false
    @State private var sshEnabled = true
    @State private var webdavEnabled = false
    @State private var readonly = false
    @State private var isSubmitting = false

    private var isValid: Bool {
        !homeDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.unit * 6) {
                        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                            SectionLabel("Home Directory")
                            GlassCard {
                                TextField("backups/app1", text: $homeDirectory)
                                    .textFieldStyle(.plain)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .hetzlyMonoNumbers()
                            }
                            Text("Relative to this Storage Box's root. Created if it doesn't already exist.")
                                .caption()
                        }

                        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                            SectionLabel("Name")
                            GlassCard {
                                TextField("Optional", text: $name)
                                    .textFieldStyle(.plain)
                                    .autocorrectionDisabled()
                            }
                        }

                        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                            SectionLabel("Description")
                            GlassCard {
                                TextField("Optional", text: $description)
                                    .textFieldStyle(.plain)
                                    .autocorrectionDisabled()
                            }
                        }

                        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                            SectionLabel("Access")
                            GlassCard {
                                VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                                    Toggle("Reachable Externally", isOn: $reachableExternally)
                                    Toggle("Samba / CIFS", isOn: $sambaEnabled)
                                    Toggle("SSH / SFTP / SCP", isOn: $sshEnabled)
                                    Toggle("WebDAV", isOn: $webdavEnabled)
                                    Toggle("Read-Only", isOn: $readonly)
                                }
                                .tint(HetzlyColors.accent)
                                .foregroundStyle(HetzlyColors.textPrimary)
                            }
                        }

                        Text("A strong password is generated automatically and shown once the subaccount is created.")
                            .caption()

                        PrimaryCTA(title: isSubmitting ? "Creating…" : "Create Subaccount", action: submit)
                            .frame(maxWidth: .infinity)
                            .disabled(!isValid || isSubmitting)
                    }
                    .padding(Spacing.screenMargin)
                }
            }
            .navigationTitle("Create Subaccount")
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
        guard isValid else { return }
        isSubmitting = true
        let trimmedHome = homeDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let settings = StorageBoxSubaccountAccessSettings(
            reachableExternally: reachableExternally,
            readonly: readonly,
            sambaEnabled: sambaEnabled,
            sshEnabled: sshEnabled,
            webdavEnabled: webdavEnabled
        )
        onCreate(
            trimmedHome,
            trimmedName.isEmpty ? nil : trimmedName,
            trimmedDescription.isEmpty ? nil : trimmedDescription,
            settings
        )
        dismiss()
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        ScrollView {
            StorageBoxSubaccountsSection(subaccounts: StorageBoxPreviewFixtures.subaccounts)
                .padding(Spacing.screenMargin)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Create Subaccount") {
    CreateSubaccountSheet(onCreate: { _, _, _, _ in })
        .preferredColorScheme(.dark)
}
