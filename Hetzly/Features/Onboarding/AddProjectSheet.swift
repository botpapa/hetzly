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

    private var canSubmit: Bool {
        !trimmedName.isEmpty && !trimmedToken.isEmpty && !isValidating
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
                                TextField("e.g. Personal, Work", text: $name)
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
                                    + "Read & Write unlocks actions; Read-only works for monitoring."
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
        let name = trimmedName
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

            do {
                _ = try container.projectsStore.addProject(name: name, token: token)
                dismiss()
            } catch {
                errorMessage = "The token is valid, but the project couldn't be saved on this device. Please try again."
            }
        }
    }
}

#Preview {
    AddProjectSheet()
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}
