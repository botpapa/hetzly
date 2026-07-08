import SwiftUI

/// Labels editor: key = value rows with add/remove, saved as one
/// `updateLabels` call (a plain PUT, not Action-tracked). Basic validation
/// mirrors Hetzner's rules loosely: keys must be non-empty and unique;
/// empty values are allowed.
struct ServerLabelsEditorSheet: View {
    /// Mutable working copy of one label.
    private struct LabelRow: Identifiable {
        let id = UUID()
        var key: String
        var value: String
    }

    let serverName: String
    let labels: [String: String]
    let isSaving: Bool
    let saveError: String?
    var onSave: ([String: String]) -> Void
    var onCancel: () -> Void

    @State private var rows: [LabelRow] = []
    @State private var didLoad = false

    private var duplicateKeys: Set<String> {
        var seen: Set<String> = []
        var duplicates: Set<String> = []
        for row in rows {
            let key = row.key.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            if !seen.insert(key).inserted {
                duplicates.insert(key)
            }
        }
        return duplicates
    }

    private var canSave: Bool {
        !isSaving
            && duplicateKeys.isEmpty
            && rows.allSatisfy { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty || $0.value.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            HStack(spacing: Spacing.unit * 3) {
                Image(systemName: "tag")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(HetzlyColors.accent)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit Labels")
                        .bodyPrimary()
                        .fontWeight(.semibold)
                    Text(serverName)
                        .caption()
                }
                Spacer()
            }

            ScrollView {
                VStack(spacing: Spacing.unit * 2) {
                    ForEach($rows) { $row in
                        labelRow($row)
                    }

                    Button {
                        withAnimation(.snappy) { rows.append(LabelRow(key: "", value: "")) }
                    } label: {
                        Label("Add Label", systemImage: "plus.circle.fill")
                            .foregroundStyle(HetzlyColors.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, Spacing.unit * 2)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !duplicateKeys.isEmpty {
                Text("Duplicate keys: \(duplicateKeys.sorted().joined(separator: ", "))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HetzlyColors.destructive)
            }

            if let saveError {
                Text(saveError)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HetzlyColors.destructive)
            }

            HStack(spacing: Spacing.unit * 3) {
                Button("Cancel", action: onCancel)
                    .secondaryCTAStyle()
                    .frame(maxWidth: .infinity)
                    .disabled(isSaving)

                PrimaryCTA(title: isSaving ? "Saving…" : "Save Labels") {
                    onSave(collectedLabels)
                }
                .frame(maxWidth: .infinity)
                .disabled(!canSave)
            }
        }
        .padding(Spacing.screenMargin)
        .padding(.top, Spacing.unit * 2)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground { CanvasBackground() }
        .presentationCornerRadius(Radius.card)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            rows = labels
                .sorted { $0.key < $1.key }
                .map { LabelRow(key: $0.key, value: $0.value) }
        }
    }

    private func labelRow(_ row: Binding<LabelRow>) -> some View {
        HStack(spacing: Spacing.unit * 2) {
            TextField("key", text: row.key)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(HetzlyColors.textPrimary)
                .padding(Spacing.unit * 2.5)
                .background(fieldBackground)

            Text("=")
                .caption()

            TextField("value", text: row.value)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(HetzlyColors.textPrimary)
                .padding(Spacing.unit * 2.5)
                .background(fieldBackground)

            Button {
                withAnimation(.snappy) {
                    rows.removeAll { $0.id == row.wrappedValue.id }
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(HetzlyColors.destructive)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove label \(row.wrappedValue.key)")
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            .fill(Color.white.opacity(0.06))
    }

    private var collectedLabels: [String: String] {
        var result: [String: String] = [:]
        for row in rows {
            let key = row.key.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            result[key] = row.value.trimmingCharacters(in: .whitespaces)
        }
        return result
    }
}

#Preview {
    ZStack {
        CanvasBackground()
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: .constant(true)) {
        ServerLabelsEditorSheet(
            serverName: "hetzi-prod-01",
            labels: ["env": "prod", "team": "core"],
            isSaving: false,
            saveError: nil,
            onSave: { _ in },
            onCancel: {}
        )
    }
}
