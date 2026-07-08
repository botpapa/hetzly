import HetznerKit
import SwiftUI

/// Step 4: name (with a regenerate button), SSH key / network / firewall
/// multi-select, public networking toggles, backups, and an optional
/// cloud-init user-data editor.
struct ConfigStepView: View {
    @Bindable var viewModel: CreateServerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 5) {
            nameSection
            sshKeysSection
            networkingSection
            if !viewModel.networks.isEmpty {
                networksSection
            }
            if !viewModel.firewalls.isEmpty {
                firewallsSection
            }
            backupsSection
            userDataSection
        }
    }

    // MARK: - Name

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Name")
            GlassCard {
                HStack(spacing: Spacing.unit * 3) {
                    TextField("Server name", text: $viewModel.name)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        withAnimation(.snappy) { viewModel.regenerateName() }
                    } label: {
                        Image(systemName: "dice")
                            .foregroundStyle(HetzlyColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Generate a new name")
                }
            }
            if !viewModel.name.isEmpty, !viewModel.isNameValid {
                Text("Use letters, digits, hyphens, and dots — it can't start or end with one.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HetzlyColors.destructive)
            }
        }
    }

    // MARK: - SSH keys

    private var sshKeysSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("SSH Keys")
            if viewModel.sshKeys.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                        Label("No SSH keys yet", systemImage: "key.slash")
                            .bodyPrimary()
                        Text("Add keys in Resources → SSH Keys — password login is emailed otherwise.")
                            .caption()
                    }
                }
            } else {
                GlassCard {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.sshKeys.enumerated()), id: \.element.id) { index, key in
                            multiSelectRow(
                                title: key.name,
                                subtitle: key.fingerprint,
                                isSelected: viewModel.sshKeyIDs.contains(key.id)
                            ) {
                                toggle(key.id, in: &viewModel.sshKeyIDs)
                            }
                            if index != viewModel.sshKeys.count - 1 {
                                Divider().overlay(HetzlyColors.textTertiary.opacity(0.15))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Public networking

    private var networkingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Public Networking")
            GlassCard {
                VStack(spacing: Spacing.unit * 3) {
                    Toggle("Public IPv4", isOn: $viewModel.ipv4Enabled)
                        .tint(HetzlyColors.accent)
                    Divider().overlay(HetzlyColors.textTertiary.opacity(0.15))
                    Toggle("Public IPv6", isOn: $viewModel.ipv6Enabled)
                        .tint(HetzlyColors.accent)
                }
            }
        }
    }

    // MARK: - Networks / firewalls

    private var networksSection: some View {
        DisclosureGroup {
            GlassCard {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.networks.enumerated()), id: \.element.id) { index, network in
                        multiSelectRow(
                            title: network.name,
                            subtitle: network.ipRange,
                            isSelected: viewModel.networkIDs.contains(network.id)
                        ) {
                            toggle(network.id, in: &viewModel.networkIDs)
                        }
                        if index != viewModel.networks.count - 1 {
                            Divider().overlay(HetzlyColors.textTertiary.opacity(0.15))
                        }
                    }
                }
            }
            .padding(.top, Spacing.unit * 2)
        } label: {
            Text(viewModel.networkIDs.isEmpty ? "Networks" : "Networks · \(viewModel.networkIDs.count)")
                .bodyPrimary()
                .fontWeight(.semibold)
        }
        .tint(HetzlyColors.textPrimary)
    }

    private var firewallsSection: some View {
        DisclosureGroup {
            GlassCard {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.firewalls.enumerated()), id: \.element.id) { index, firewall in
                        multiSelectRow(
                            title: firewall.name,
                            subtitle: "\(firewall.rules.count) rule\(firewall.rules.count == 1 ? "" : "s")",
                            isSelected: viewModel.firewallIDs.contains(firewall.id)
                        ) {
                            toggle(firewall.id, in: &viewModel.firewallIDs)
                        }
                        if index != viewModel.firewalls.count - 1 {
                            Divider().overlay(HetzlyColors.textTertiary.opacity(0.15))
                        }
                    }
                }
            }
            .padding(.top, Spacing.unit * 2)
        } label: {
            Text(viewModel.firewallIDs.isEmpty ? "Firewalls" : "Firewalls · \(viewModel.firewallIDs.count)")
                .bodyPrimary()
                .fontWeight(.semibold)
        }
        .tint(HetzlyColors.textPrimary)
    }

    // MARK: - Backups

    private var backupsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Backups")
            GlassCard {
                Toggle(isOn: $viewModel.backupsEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatic Backups").bodyPrimary()
                        Text(backupsSubtitle).caption()
                    }
                }
                .tint(HetzlyColors.accent)
            }
        }
    }

    private var backupsSubtitle: String {
        guard let delta = viewModel.backupsMonthlyDelta else { return "+20% of the server price" }
        return "+20% · \(CurrencyFormat.string(delta, currencyCode: viewModel.currencyCode))/mo"
    }

    // MARK: - Cloud-init

    private var userDataSection: some View {
        DisclosureGroup {
            TextEditor(text: $viewModel.userData)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 140)
                .scrollContentBackground(.hidden)
                .padding(Spacing.unit * 2)
                .background {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                }
                .padding(.top, Spacing.unit * 2)
        } label: {
            Text("Cloud-Init User Data")
                .bodyPrimary()
                .fontWeight(.semibold)
        }
        .tint(HetzlyColors.textPrimary)
    }

    // MARK: - Shared row

    private func multiSelectRow(title: String, subtitle: String, isSelected: Bool, onToggle: @escaping () -> Void) -> some View {
        Button(action: onToggle) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).bodyPrimary()
                    Text(subtitle).caption()
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? HetzlyColors.accent : HetzlyColors.textTertiary)
            }
            .padding(.vertical, Spacing.unit * 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func toggle(_ id: Int, in set: inout Set<Int>) {
        if set.contains(id) {
            set.remove(id)
        } else {
            set.insert(id)
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        ScrollView {
            ConfigStepView(viewModel: CreateServerPreviewFixtures.configuredViewModel())
                .padding(Spacing.screenMargin)
        }
    }
    .preferredColorScheme(.dark)
}
