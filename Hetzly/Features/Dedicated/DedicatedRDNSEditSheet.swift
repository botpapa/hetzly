import SwiftUI

/// Reverse-DNS edit sheet for a single dedicated-server IP: a PTR hostname
/// field, with an explicit "Reset to default" that deletes the record
/// (Robot then serves no custom PTR for that IP). Mirrors the Resources
/// tab's IP detail rDNS editor.
struct DedicatedRDNSEditSheet: View {
    let ip: String
    let currentPTR: String?
    /// `nil` means "reset to default" (→ `deleteRDNS`); non-nil means "set"
    /// (→ `setRDNS`).
    var onSave: (String?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var ptr: String
    @State private var isSubmitting = false

    init(ip: String, currentPTR: String?, onSave: @escaping (String?) async -> Void) {
        self.ip = ip
        self.currentPTR = currentPTR
        self.onSave = onSave
        self._ptr = State(initialValue: currentPTR ?? "")
    }

    private var trimmedPTR: String {
        ptr.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            Text("Reverse DNS").bodyPrimary().fontWeight(.semibold)
            Text(ip).hetzlyMonoNumbers().foregroundStyle(HetzlyColors.textSecondary)

            GlassCard {
                TextField("ptr.example.com", text: $ptr)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .hetzlyMonoNumbers()
            }

            Button("Reset to Hetzner default") {
                submit(delete: true)
            }
            .secondaryCTAStyle()
            .disabled(isSubmitting)

            Spacer(minLength: 0)

            HStack(spacing: Spacing.unit * 3) {
                Button("Cancel") { dismiss() }.secondaryCTAStyle().frame(maxWidth: .infinity)
                PrimaryCTA(title: isSubmitting ? "Saving…" : "Save") {
                    submit(delete: false)
                }
                .frame(maxWidth: .infinity)
                .disabled(isSubmitting || trimmedPTR.isEmpty)
            }
        }
        .padding(Spacing.screenMargin)
        .padding(.top, Spacing.unit * 2)
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        .presentationBackground { CanvasBackground() }
        .presentationCornerRadius(Radius.card)
    }

    private func submit(delete: Bool) {
        isSubmitting = true
        Task {
            await onSave(delete ? nil : trimmedPTR)
            isSubmitting = false
            dismiss()
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: .constant(true)) {
        DedicatedRDNSEditSheet(ip: "95.216.3.171", currentPTR: "host.example.com") { _ in }
    }
}
