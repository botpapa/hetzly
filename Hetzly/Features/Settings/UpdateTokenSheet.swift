import HetznerKit
import SwiftUI

/// Replaces a project's Hetzner Cloud API token in place — for a revoked or
/// rotated key — without deleting and re-adding the project (which would
/// also lose its cached server snapshots and sort position).
///
/// Reusable: presented from `SettingsView`'s project row context menu today;
/// the Dashboard's per-project 401 error row is meant to reach the same
/// sheet at integration (see `CONTRACTS.md`'s multi-project wave section).
struct UpdateTokenSheet: View {
    let project: ProjectRecord

    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var token = ""
    @State private var isValidating = false
    @State private var errorMessage: String?
    @State private var successHaptic = false
    @FocusState private var isTokenFocused: Bool

    private var trimmedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
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
                            SectionLabel("New API token")
                            GlassCard {
                                SecureTokenField(placeholder: "hcloud_...", text: $token)
                                    .focused($isTokenFocused)
                                    .submitLabel(.done)
                                    .onSubmit(submit)
                            }
                            Text(
                                "Paste a new API token for \"\(project.name)\". "
                                    + "The old one is replaced on this device only."
                            )
                            .caption()
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(HetzlyColors.destructive)
                        }

                        PrimaryCTA(title: isValidating ? "Validating…" : "Update Token", action: submit)
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
            .navigationTitle("Update Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isValidating)
                }
            }
            .onAppear { isTokenFocused = true }
        }
        .interactiveDismissDisabled(isValidating)
        .sensoryFeedback(.success, trigger: successHaptic)
    }

    /// Validates the new token against the live API before persisting
    /// anything — an invalid token never overwrites a working one. Guarded
    /// by `isValidating` so a double-tap can never fire a second request
    /// while one is already in flight.
    private func submit() {
        guard canSubmit else { return }

        errorMessage = nil
        isValidating = true
        let newToken = trimmedToken

        Task {
            defer { isValidating = false }

            let client = CloudClient(token: newToken)
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
                try container.projectsStore.updateToken(for: project, to: newToken)
                container.invalidateCloudClient(for: project.id)
                successHaptic.toggle()
                // Let the sensory feedback register before the sheet leaves
                // the hierarchy.
                try? await Task.sleep(for: .milliseconds(200))
                dismiss()
            } catch {
                errorMessage = "The token is valid, but it couldn't be saved on this device. Please try again."
            }
        }
    }
}

#Preview {
    UpdateTokenSheet(project: ProjectRecord(name: "Personal", sortOrder: 0))
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}
