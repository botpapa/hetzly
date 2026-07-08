import HetznerKit
import SwiftUI

/// Collects a label plus Hetzner Robot webservice credentials, validates
/// them against the live API, and saves the account on success.
///
/// Hard client-side constraint (spec-mandated, see `CONTRACTS.md`): adding
/// an account fires **exactly one** login attempt per tap of "Add Account" —
/// never an automatic retry loop — because Robot bans the source IP for 10
/// minutes after 3 failed logins. A 401 response surfaces a prominent
/// warning card (not just inline error text) so the user understands that
/// risk before they manually try again.
///
/// Presented from `SettingsView`'s "Add Robot Account" row — the Robot
/// equivalent of `AddProjectSheet`.
struct AddRobotAccountSheet: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isValidating = false
    @State private var errorMessage: String?
    /// Set once a validation attempt has come back `401 unauthorized`. Stays
    /// set (even across further edits) until the sheet is dismissed or a
    /// later attempt succeeds — the ban-risk warning should stay visible for
    /// as long as the user might be tempted to just mash "Add Account"
    /// again.
    @State private var showedUnauthorizedWarning = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case label
        case username
        case password
    }

    private var trimmedLabel: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedLabel.isEmpty && !trimmedUsername.isEmpty && !password.isEmpty && !isValidating
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
                                TextField("e.g. Dedicated Servers", text: $label)
                                    .textFieldStyle(.plain)
                                    .textInputAutocapitalization(.words)
                                    .autocorrectionDisabled()
                                    .focused($focusedField, equals: .label)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .username }
                            }
                        }

                        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                            SectionLabel("Webservice username")
                            GlassCard {
                                TextField("#ws+...", text: $username)
                                    .textFieldStyle(.plain)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.asciiCapable)
                                    .hetzlyMonoNumbers()
                                    .focused($focusedField, equals: .username)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .password }
                            }
                        }

                        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                            SectionLabel("Password")
                            GlassCard {
                                SecureTokenField(placeholder: "Password", text: $password)
                                    .focused($focusedField, equals: .password)
                                    .submitLabel(.done)
                                    .onSubmit(submit)
                            }
                            Text(
                                "Create a webservice user in Robot → Settings → Webservice. "
                                    + "This is NOT your main Hetzner account login."
                            )
                            .caption()
                        }

                        if showedUnauthorizedWarning {
                            unauthorizedWarningCard
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
            .navigationTitle("Add Robot Account")
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

    private var unauthorizedWarningCard: some View {
        GlassCard {
            HStack(alignment: .top, spacing: Spacing.unit * 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(HetzlyColors.destructive)
                VStack(alignment: .leading, spacing: Spacing.unit) {
                    Text("Wrong credentials")
                        .bodyPrimary()
                        .fontWeight(.semibold)
                    Text("Careful: 3 failed logins ban your IP for 10 minutes.")
                        .bodySecondary()
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Fires exactly one `validateCredentials()` call. Guarded by
    /// `isValidating` so a double-tap (or return-key + button tap) can never
    /// fire a second request while one is already in flight — this app never
    /// retries a Robot login automatically.
    private func submit() {
        guard canSubmit else { return }

        errorMessage = nil
        isValidating = true
        let label = trimmedLabel
        let username = trimmedUsername
        let password = password

        Task {
            defer { isValidating = false }

            let client = RobotClient(username: username, password: password)
            do {
                try await client.validateCredentials()
            } catch let apiError as HetznerAPIError {
                if case .unauthorized = apiError {
                    showedUnauthorizedWarning = true
                }
                errorMessage = apiError.userMessage
                return
            } catch {
                errorMessage = "Couldn't reach Hetzner Robot right now. Check your connection and try again."
                return
            }

            do {
                _ = try container.robotAccountsStore.addAccount(label: label, username: username, password: password)
                dismiss()
            } catch {
                errorMessage = "The credentials are valid, but the account couldn't be saved on this device. Please try again."
            }
        }
    }
}

#Preview {
    AddRobotAccountSheet()
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}
