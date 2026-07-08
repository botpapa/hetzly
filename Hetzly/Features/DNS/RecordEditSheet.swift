import HetznerKit
import SwiftUI

/// Add/edit sheet for a DNS record set: name (with an "@" apex hint), type
/// picker, TTL presets (300/3600/86400/custom), and a per-type values editor
/// — a single validated field for A/AAAA/CNAME, priority + hostname for MX,
/// and one-value-per-line free text for TXT and the long tail. When editing,
/// name and type are fixed (they're the record set's identity in the API).
struct RecordEditSheet: View {
    var existingRecordSet: DNSRecordSet?
    var onSave: (_ name: String, _ type: DNSRecordType, _ ttl: Int?, _ values: [String]) -> Void
    var onCancel: () -> Void

    @State private var name: String
    @State private var recordType: DNSRecordType
    @State private var ttlPreset: TTLPreset
    @State private var customTTLText: String
    @State private var singleValue: String
    @State private var mxPriorityText: String
    @State private var mxHost: String
    @State private var multilineValues: String
    @State private var validationMessage: String?

    init(
        existingRecordSet: DNSRecordSet?,
        onSave: @escaping (_ name: String, _ type: DNSRecordType, _ ttl: Int?, _ values: [String]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.existingRecordSet = existingRecordSet
        self.onSave = onSave
        self.onCancel = onCancel

        let type = existingRecordSet?.type ?? .a
        _name = State(initialValue: existingRecordSet?.name ?? "")
        _recordType = State(initialValue: type)
        _ttlPreset = State(initialValue: TTLPreset.matching(ttl: existingRecordSet?.ttl))
        _customTTLText = State(initialValue: existingRecordSet?.ttl.map(String.init) ?? "")

        let values = existingRecordSet?.records.map(\.value) ?? []
        if type == .mx, let first = values.first {
            let parts = first.split(separator: " ", maxSplits: 1)
            _mxPriorityText = State(initialValue: parts.count == 2 ? String(parts[0]) : "10")
            _mxHost = State(initialValue: parts.count == 2 ? String(parts[1]) : first)
            _singleValue = State(initialValue: "")
        } else {
            _mxPriorityText = State(initialValue: "10")
            _mxHost = State(initialValue: "")
            _singleValue = State(initialValue: type.usesMultilineValues ? "" : (values.first ?? ""))
        }
        _multilineValues = State(initialValue: type.usesMultilineValues ? values.joined(separator: "\n") : "")
    }

    private var isEditing: Bool { existingRecordSet != nil }

    private var trimmedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "@" : trimmed
    }

    private var resolvedTTL: Int? {
        if let seconds = ttlPreset.seconds { return seconds }
        return Int(customTTLText)
    }

    private var resolvedValues: [String] {
        if recordType == .mx {
            let host = mxHost.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty else { return [] }
            return ["\(mxPriorityText.trimmingCharacters(in: .whitespaces)) \(host)"]
        }
        if recordType.usesMultilineValues {
            return multilineValues
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        let value = singleValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? [] : [value]
    }

    private var canSave: Bool {
        guard !resolvedValues.isEmpty else { return false }
        if ttlPreset == .custom, resolvedTTL == nil { return false }
        return resolvedValues.allSatisfy { DNSRecordValidator.isValid($0, for: recordType) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.unit * 7) {
                        nameSection
                        typeSection
                        ttlSection
                        valuesSection
                    }
                    .padding(Spacing.screenMargin)
                }
            }
            .navigationTitle(isEditing ? "Edit Record" : "New Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
        }
    }

    // MARK: - Name

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Name")
            GlassCard {
                TextField("@", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(isEditing)
                    .opacity(isEditing ? 0.5 : 1)
            }
            Text(isEditing
                ? "Name and type identify this record set and can't be changed."
                : "Use \"@\" (or leave empty) for the zone apex.")
                .caption()
        }
    }

    // MARK: - Type

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Type")
            if isEditing {
                GlassChip(recordType.rawValue)
                    .opacity(0.6)
            } else {
                FlowLayout(spacing: Spacing.unit * 2) {
                    ForEach(DNSRecordType.editableCases, id: \.rawValue) { type in
                        Button {
                            withAnimation(.snappy) {
                                recordType = type
                                validationMessage = nil
                            }
                        } label: {
                            Text(type.rawValue)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(recordType == type ? HetzlyColors.textPrimary : HetzlyColors.textSecondary)
                                .padding(.horizontal, Spacing.unit * 3)
                                .padding(.vertical, Spacing.unit * 1.5)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(recordType == type ? HetzlyColors.accent.opacity(0.9) : Color.white.opacity(0.06))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - TTL

    private var ttlSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("TTL")
            InlineSegmentedPicker(options: TTLPreset.allCases, selection: $ttlPreset, label: \.label)
            if ttlPreset == .custom {
                GlassCard {
                    TextField("Seconds, e.g. 600", text: $customTTLText)
                        .textFieldStyle(.plain)
                        .keyboardType(.numberPad)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
    }

    // MARK: - Values

    @ViewBuilder
    private var valuesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel(recordType == .txt ? "Values (one per line)" : "Value")

            if recordType == .mx {
                mxEditor
            } else if recordType.usesMultilineValues {
                GlassCard {
                    TextEditor(text: $multilineValues)
                        .font(.system(size: 14, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 96)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } else {
                GlassCard {
                    TextField(recordType.valuePlaceholder, text: $singleValue)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(recordType == .a ? .decimalPad : .asciiCapable)
                }
            }

            if let message = liveValidationMessage {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(HetzlyColors.destructive)
            }
        }
    }

    private var mxEditor: some View {
        GlassCard {
            VStack(spacing: Spacing.unit * 3) {
                HStack {
                    Text("Priority").bodySecondary()
                    Spacer()
                    TextField("10", text: $mxPriorityText)
                        .textFieldStyle(.plain)
                        .keyboardType(.numberPad)
                        .font(.system(.body, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100)
                }
                Divider().overlay(HetzlyColors.textTertiary.opacity(0.2))
                HStack {
                    Text("Mail server").bodySecondary()
                    Spacer()
                    TextField("mail.example.com.", text: $mxHost)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
        }
    }

    private var liveValidationMessage: String? {
        let values = resolvedValues
        guard !values.isEmpty else { return nil }
        guard let invalid = values.first(where: { !DNSRecordValidator.isValid($0, for: recordType) }) else {
            return nil
        }
        switch recordType {
        case .a: return "\"\(invalid)\" isn't a valid IPv4 address."
        case .aaaa: return "\"\(invalid)\" isn't a valid IPv6 address."
        case .cname, .ns, .ptr: return "\"\(invalid)\" isn't a valid hostname."
        case .mx: return "Enter a priority (0–65535) and a valid mail server hostname."
        default: return "\"\(invalid)\" doesn't look valid for \(recordType.rawValue)."
        }
    }

    private func save() {
        guard canSave else { return }
        onSave(trimmedName, recordType, resolvedTTL, resolvedValues)
    }
}

#Preview("New record") {
    RecordEditSheet(existingRecordSet: nil, onSave: { _, _, _, _ in }, onCancel: {})
        .preferredColorScheme(.dark)
}

#Preview("Edit MX") {
    RecordEditSheet(
        existingRecordSet: DNSPreviewFixtures.recordSets[3],
        onSave: { _, _, _, _ in },
        onCancel: {}
    )
    .preferredColorScheme(.dark)
}
