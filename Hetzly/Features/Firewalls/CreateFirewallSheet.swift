import HetznerKit
import SwiftUI

/// Collects a firewall name and creates it. Rules are added afterward, from
/// `FirewallDetailView` — this sheet is intentionally name-only.
struct CreateFirewallSheet: View {
    @Environment(\.dismiss) private var dismiss

    var onCreate: (String) async -> Result<Firewall, DisplayError>
    var onCreated: (Firewall) -> Void

    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSubmit: Bool { !trimmedName.isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()
                VStack(alignment: .leading, spacing: Spacing.unit * 6) {
                    VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                        SectionLabel("Name")
                        GlassCard {
                            TextField("e.g. web-servers", text: $name)
                                .textFieldStyle(.plain)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($isFocused)
                                .submitLabel(.done)
                                .onSubmit(submit)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(HetzlyColors.destructive)
                    }

                    PrimaryCTA(title: isSaving ? "Creating…" : "Create Firewall", action: submit)
                        .frame(maxWidth: .infinity)
                        .disabled(!canSubmit)

                    Spacer(minLength: 0)
                }
                .padding(Spacing.screenMargin)
            }
            .navigationTitle("New Firewall")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .onAppear { isFocused = true }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private func submit() {
        guard canSubmit else { return }
        errorMessage = nil
        isSaving = true
        let name = trimmedName
        Task {
            defer { isSaving = false }
            switch await onCreate(name) {
            case .success(let firewall):
                onCreated(firewall)
                dismiss()
            case .failure(let error):
                errorMessage = error.message
            }
        }
    }
}

#Preview {
    CreateFirewallSheet(onCreate: { _ in .success(FirewallPreviewFixtures.bareFirewall) }, onCreated: { _ in })
        .preferredColorScheme(.dark)
}
