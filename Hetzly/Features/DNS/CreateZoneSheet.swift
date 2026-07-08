import HetznerKit
import SwiftUI

/// Create-zone sheet: zone name plus a default TTL preset.
struct CreateZoneSheet: View {
    @Environment(\.dismiss) private var dismiss

    var onCreate: (String, Int?) async -> Result<DNSZone, DisplayError>
    var onCreated: (DNSZone) -> Void

    @State private var name = ""
    @State private var ttlPreset: TTLPreset = .oneHour
    @State private var customTTLText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isNameFocused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    private var resolvedTTL: Int? {
        if let seconds = ttlPreset.seconds { return seconds }
        return Int(customTTLText)
    }

    private var canSubmit: Bool {
        guard !isSaving, DNSRecordValidator.isHostname(trimmedName), trimmedName.contains(".") else { return false }
        if ttlPreset == .custom {
            guard let ttl = Int(customTTLText), ttl > 0 else { return false }
        }
        return true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.unit * 6) {
                        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                            SectionLabel("Zone Name")
                            GlassCard {
                                TextField("example.com", text: $name)
                                    .textFieldStyle(.plain)
                                    .font(.system(.body, design: .monospaced))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.URL)
                                    .focused($isNameFocused)
                            }
                        }

                        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                            SectionLabel("Default TTL")
                            InlineSegmentedPicker(
                                options: TTLPreset.allCases,
                                selection: $ttlPreset,
                                label: \.label
                            )
                            if ttlPreset == .custom {
                                GlassCard {
                                    TextField("Seconds, e.g. 600", text: $customTTLText)
                                        .textFieldStyle(.plain)
                                        .keyboardType(.numberPad)
                                        .font(.system(.body, design: .monospaced))
                                }
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(HetzlyColors.destructive)
                        }

                        PrimaryCTA(title: isSaving ? "Creating…" : "Create Zone", action: submit)
                            .frame(maxWidth: .infinity)
                            .disabled(!canSubmit)
                    }
                    .padding(Spacing.screenMargin)
                }
            }
            .navigationTitle("New Zone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .onAppear { isNameFocused = true }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private func submit() {
        guard canSubmit else { return }
        errorMessage = nil
        isSaving = true
        let name = trimmedName
        let ttl = resolvedTTL

        Task {
            defer { isSaving = false }
            switch await onCreate(name, ttl) {
            case .success(let zone):
                onCreated(zone)
                dismiss()
            case .failure(let error):
                errorMessage = error.message
            }
        }
    }
}

#Preview {
    CreateZoneSheet(onCreate: { _, _ in .success(DNSPreviewFixtures.zone) }, onCreated: { _ in })
        .preferredColorScheme(.dark)
}
