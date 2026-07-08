import HetznerKit
import SwiftUI

/// Add/edit sheet for a single firewall rule. Direction is fixed by the
/// section it was opened from (inbound → editing `sourceIPs`, outbound →
/// `destinationIPs`) — the sheet never lets the user change it.
struct RuleEditSheet: View {
    let direction: FirewallDirection
    var existingRule: FirewallRule?
    var onSave: (FirewallRule) -> Void
    var onCancel: () -> Void

    @State private var networkProtocol: FirewallProtocol
    @State private var portText: String
    @State private var cidrs: [String]
    @State private var newCIDRText = ""
    @State private var description: String
    @State private var portError: String?
    @State private var cidrError: String?

    init(
        direction: FirewallDirection,
        existingRule: FirewallRule?,
        onSave: @escaping (FirewallRule) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.direction = direction
        self.existingRule = existingRule
        self.onSave = onSave
        self.onCancel = onCancel
        _networkProtocol = State(initialValue: existingRule?.networkProtocol ?? .tcp)
        _portText = State(initialValue: existingRule?.port ?? "")
        _cidrs = State(initialValue: existingRule.map { direction == .inbound ? $0.sourceIPs : $0.destinationIPs } ?? [])
        _description = State(initialValue: existingRule?.description ?? "")
    }

    private var addressLabel: String { direction == .inbound ? "Source" : "Destination" }

    private var canSave: Bool {
        guard !cidrs.isEmpty else { return false }
        return networkProtocol.showsPort ? PortValidator.isValid(portText) : true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.unit * 7) {
                        protocolSection
                        if networkProtocol.showsPort { portSection }
                        cidrSection
                        descriptionSection
                    }
                    .padding(Spacing.screenMargin)
                }
            }
            .navigationTitle(existingRule == nil ? "New Rule" : "Edit Rule")
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

    // MARK: - Protocol

    private var protocolSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            HStack {
                SectionLabel("Protocol")
                Spacer()
                templatesMenu
            }
            InlineSegmentedPicker(
                options: FirewallProtocol.editableCases,
                selection: $networkProtocol,
                label: \.displayName
            )
        }
    }

    private var templatesMenu: some View {
        Menu {
            ForEach(RuleTemplate.all) { template in
                Button(template.name) { apply(template) }
            }
        } label: {
            Label("Templates", systemImage: "list.bullet.rectangle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(HetzlyColors.accent)
        }
    }

    private func apply(_ template: RuleTemplate) {
        networkProtocol = template.networkProtocol
        portText = template.port ?? ""
        if description.isEmpty { description = template.description }
        portError = nil
    }

    // MARK: - Port

    private var portSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Port")
            GlassCard {
                TextField("80 or 80-85", text: $portText)
                    .textFieldStyle(.plain)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: portText) { _, newValue in
                        portError = (newValue.isEmpty || PortValidator.isValid(newValue))
                            ? nil
                            : "Enter a port like \"80\" or a range like \"80-85\"."
                    }
            }
            if let portError {
                Text(portError)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(HetzlyColors.destructive)
            }
        }
    }

    // MARK: - CIDRs

    private var cidrSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            HStack {
                SectionLabel(addressLabel)
                Spacer()
                presetsMenu
            }

            if !cidrs.isEmpty {
                FlowLayout(spacing: Spacing.unit * 2) {
                    ForEach(cidrs, id: \.self) { cidr in
                        HStack(spacing: Spacing.unit) {
                            Text(cidr).font(.system(size: 13, design: .monospaced))
                            Button { remove(cidr) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                            }
                            .accessibilityLabel("Remove \(cidr)")
                        }
                        .foregroundStyle(HetzlyColors.textPrimary)
                        .padding(.horizontal, Spacing.unit * 2.5)
                        .padding(.vertical, Spacing.unit * 1.5)
                        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.08)))
                    }
                }
            }

            GlassCard {
                HStack {
                    TextField("e.g. 203.0.113.0/24", text: $newCIDRText)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .onSubmit(addCIDR)
                    Button(action: addCIDR) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(HetzlyColors.accent)
                    }
                    .disabled(newCIDRText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if let cidrError {
                Text(cidrError)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(HetzlyColors.destructive)
            } else if cidrs.isEmpty {
                Text("Add at least one \(addressLabel.lowercased()) CIDR.").caption()
            }
        }
    }

    private var presetsMenu: some View {
        Menu {
            Button("Any IPv4 · 0.0.0.0/0") { addPreset("0.0.0.0/0") }
            Button("Any IPv6 · ::/0") { addPreset("::/0") }
        } label: {
            Label("Presets", systemImage: "globe")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(HetzlyColors.accent)
        }
    }

    private func addPreset(_ cidr: String) {
        guard !cidrs.contains(cidr) else { return }
        cidrs.append(cidr)
        cidrError = nil
    }

    private func addCIDR() {
        let trimmed = newCIDRText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard CIDRValidator.isValid(trimmed) else {
            cidrError = "\"\(trimmed)\" isn't a valid CIDR. Try something like 203.0.113.0/24 or 2001:db8::/32."
            return
        }
        guard !cidrs.contains(trimmed) else {
            newCIDRText = ""
            return
        }
        cidrs.append(trimmed)
        newCIDRText = ""
        cidrError = nil
    }

    private func remove(_ cidr: String) {
        cidrs.removeAll { $0 == cidr }
    }

    // MARK: - Description

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Description")
            GlassCard {
                TextField("Optional", text: $description)
                    .textFieldStyle(.plain)
            }
        }
    }

    // MARK: - Save

    private func save() {
        guard canSave else { return }
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let rule = FirewallRule(
            direction: direction,
            networkProtocol: networkProtocol,
            port: networkProtocol.showsPort ? portText.trimmingCharacters(in: .whitespaces) : nil,
            sourceIPs: direction == .inbound ? cidrs : [],
            destinationIPs: direction == .outbound ? cidrs : [],
            description: trimmedDescription.isEmpty ? nil : trimmedDescription
        )
        onSave(rule)
    }
}

#Preview("New rule") {
    RuleEditSheet(direction: .inbound, existingRule: nil, onSave: { _ in }, onCancel: {})
        .preferredColorScheme(.dark)
}

#Preview("Edit rule") {
    RuleEditSheet(
        direction: .inbound,
        existingRule: FirewallPreviewFixtures.webFirewall.rules[0],
        onSave: { _ in },
        onCancel: {}
    )
    .preferredColorScheme(.dark)
}
