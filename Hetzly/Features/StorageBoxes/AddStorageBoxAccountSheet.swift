import HetznerKit
import SwiftUI

/// Collects a label plus a Hetzner Storage Box API token, validates it
/// against the live API, and saves the account on success.
///
/// Presented from `SettingsView`'s "Add Storage Box Account" row — the
/// Storage Box equivalent of `AddRobotAccountSheet` / `AddProjectSheet`.
/// Unlike Robot's Basic-auth login (capped at one attempt per the 10-minute
/// IP ban), Storage Box tokens use ordinary Bearer auth, so there's no
/// analogous attempt-limiting UI here — just a single validation call per
/// tap of "Add Account".
struct AddStorageBoxAccountSheet: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var token = ""
    @State private var isValidating = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case label
        case token
    }

    private var trimmedLabel: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedLabel.isEmpty && !trimmedToken.isEmpty && !isValidating
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.unit * 7) {
                        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                            SectionLabel("Label")
                            GlassCard {
                                TextField("e.g. Backups", text: $label)
                                    .textFieldStyle(.plain)
                                    .textInputAutocapitalization(.words)
                                    .autocorrectionDisabled()
                                    .focused($focusedField, equals: .label)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .token }
                            }
                        }

                        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                            SectionLabel("API Token")
                            GlassCard {
                                SecureTokenField(placeholder: "Storage Box API Token", text: $token)
                                    .focused($focusedField, equals: .token)
                                    .submitLabel(.done)
                                    .onSubmit(submit)
                            }
                            Text(
                                "Create a token for Storage Boxes in console.hetzner.com — Storage Boxes use "
                                    + "Hetzner's new API, separate from Cloud project tokens."
                            )
                            .caption()
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(HetzlyColors.destructive)
                        }

                        PrimaryCTA(title: isValidating ? "Validating…" : "Add Account", action: submit)
                            .frame(maxWidth: .infinity)
                            .disabled(!canSubmit)
                            .overlay(alignment: .trailing) {
                                if isValidating {
                                    ProgressView()
                                        .tint(.white)
                                        .padding(.trailing, Spacing.unit * 4)
                                }
                            }
                    }
                    .padding(Spacing.screenMargin)
                }
            }
            .navigationTitle("Add Storage Box Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isValidating)
                }
            }
        }
        .interactiveDismissDisabled(isValidating)
    }

    private func submit() {
        guard canSubmit else { return }

        errorMessage = nil
        isValidating = true
        let label = trimmedLabel
        let token = trimmedToken

        Task {
            defer { isValidating = false }

            let client = StorageBoxClient(token: token)
            do {
                try await client.validateToken()
            } catch let apiError as HetznerAPIError {
                errorMessage = apiError.userMessage
                return
            } catch {
                errorMessage = "Couldn't reach Hetzner right now. Check your connection and try again."
                return
            }

            do {
                _ = try container.storageBoxAccountsStore.addAccount(label: label, token: token)
                dismiss()
            } catch {
                errorMessage = "The token is valid, but the account couldn't be saved on this device. Please try again."
            }
        }
    }
}

#Preview {
    AddStorageBoxAccountSheet()
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}
