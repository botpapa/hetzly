import HetznerKit
import SwiftUI

/// Collects a project name and Hetzner Cloud API token, validates the token
/// against the live API, and saves the project on success.
///
/// Reusable: presented from `OnboardingView` for the very first project and
/// from `SettingsView`'s "Add project" row for every subsequent one.
struct AddProjectSheet: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var token = ""
    @State private var isValidating = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case token
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Hetzner's API has no endpoint that reveals a project's name from its
    /// token (verified against both api.hetzner.cloud and api.hetzner.com),
    /// so when the field is left empty the name is derived from the
    /// project's server names after validation (see submit()), with this
    /// numbered fallback for empty projects.
    private var fallbackName: String {
        "Project \(container.projectsStore.projects.count + 1)"
    }

    private var canSubmit: Bool {
        !trimmedToken.isEmpty && !isValidating
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.unit * 7) {
                        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                            SectionLabel("Project name")
                            GlassCard {
                                TextField("Optional — e.g. Personal, Work", text: $name)
                                    .textFieldStyle(.plain)
                                    .textInputAutocapitalization(.words)
                                    .autocorrectionDisabled()
                                    .focused($focusedField, equals: .name)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .token }
                            }
                        }

                        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                            SectionLabel("API token")
                            GlassCard {
                                SecureTokenField(placeholder: "hcloud_...", text: $token)
                                    .focused($focusedField, equals: .token)
                                    .submitLabel(.done)
                                    .onSubmit(submit)
                            }
                            Text(
                                "Create a token in Hetzner Console → Security → API tokens. "
                                    + "Read & Write unlocks actions; Read-only works for monitoring. "
                                    + "Hetzner doesn't expose the project's name to the API — leave "
                                    + "the name blank and we'll derive one from your server names."
                            )
                            .caption()
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(HetzlyColors.destructive)
                        }

                        PrimaryCTA(title: isValidating ? "Validating…" : "Add Project", action: submit)
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
            .navigationTitle("Add Project")
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

    /// Validates the token against the live API, then persists the project.
    /// Guards against re-entrancy so a double-tap (or return-key + button
    /// tap) never fires a second request while one is already in flight.
    private func submit() {
        guard canSubmit else { return }

        errorMessage = nil
        isValidating = true
        let userProvidedName = trimmedName
        let fallbackName = fallbackName
        let token = trimmedToken

        Task {
            defer { isValidating = false }

            let client = CloudClient(token: token)
            do {
                try await client.validateToken()
            } catch let apiError as HetznerAPIError {
                errorMessage = apiError.userMessage
                return
            } catch {
                errorMessage = "Couldn't reach Hetzner right now. Check your connection and try again."
                return
            }

            var name = userProvidedName
            if name.isEmpty {
                // Best-available substitute for the unfetchable Console name:
                // derive it from the project's server naming convention.
                let serverNames = ((try? await client.listServers()) ?? []).map(\.name)
                name = ProjectNameSuggestion.suggest(fromServerNames: serverNames, fallback: fallbackName)
            }

            do {
                _ = try container.projectsStore.addProject(name: name, token: token)
                dismiss()
            } catch {
                // Almost always a Keychain denial (e.g. running an unsigned
                // development build) — surface the underlying reason so the
                // failure is diagnosable instead of a dead-end "try again".
                errorMessage = "The token is valid, but it couldn't be stored in the device Keychain: "
                    + error.localizedDescription
            }
        }
    }
}

#Preview {
    AddProjectSheet()
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}
