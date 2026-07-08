import SwiftUI

/// SSH key multi-select for the ordering flow. Robot ordering is
/// SSH-key-only — there is no password-install option — so at least one key
/// selected is a hard requirement, enforced by the caller disabling
/// "Continue" until `selection` is non-empty. When the account has no keys
/// yet, explains how to add one (Robot has no "create key" endpoint in this
/// wave — `RobotClient.listSSHKeys()` is read-only per CONTRACTS.md).
struct SSHKeyMultiSelectSection: View {
    let keys: [SSHKeyOption]
    @Binding var selection: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("SSH Keys")

            if keys.isEmpty {
                noKeysCard
            } else {
                GlassCard {
                    VStack(spacing: 0) {
                        ForEach(Array(keys.enumerated()), id: \.element.id) { index, key in
                            row(key)
                            if index != keys.count - 1 {
                                Divider().overlay(HetzlyColors.textTertiary.opacity(0.15))
                            }
                        }
                    }
                }
                Text("Robot only supports key-based logins for ordered servers — pick at least one.")
                    .caption()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var noKeysCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                Label("No SSH keys on this account", systemImage: "key.slash")
                    .bodyPrimary()
                Text("Robot requires a key for every ordered server — there's no password-install option. Add one first:")
                    .caption()
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: Spacing.unit) {
                    Text("1. Open robot.hetzner.com and sign in.").caption()
                    Text("2. Go to Server → Key Management.").caption()
                    Text("3. Upload or generate a key, then come back here.").caption()
                }
            }
        }
    }

    private func row(_ key: SSHKeyOption) -> some View {
        Button {
            withAnimation(.snappy) {
                if selection.contains(key.fingerprint) {
                    selection.remove(key.fingerprint)
                } else {
                    selection.insert(key.fingerprint)
                }
            }
        } label: {
            HStack(spacing: Spacing.unit * 3) {
                Image(systemName: selection.contains(key.fingerprint) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selection.contains(key.fingerprint) ? HetzlyColors.accent : HetzlyColors.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(key.name).bodyPrimary()
                    Text(key.fingerprint)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(HetzlyColors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            .padding(.vertical, Spacing.unit * 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection.contains(key.fingerprint) ? [.isSelected] : [])
    }
}

#Preview {
    @Previewable @State var selection: Set<String> = [OrderPreviewFixtures.sshKeys[0].fingerprint]

    return ZStack {
        CanvasBackground()
        VStack(spacing: Spacing.unit * 6) {
            SSHKeyMultiSelectSection(keys: OrderPreviewFixtures.sshKeys, selection: $selection)
            SSHKeyMultiSelectSection(keys: [], selection: .constant([]))
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
