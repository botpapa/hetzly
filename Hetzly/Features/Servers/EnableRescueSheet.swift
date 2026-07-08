import HetznerKit
import SwiftUI

/// Sheet for enabling rescue mode: multi-select the project's SSH keys (or
/// none, in which case Hetzner issues a one-time root password) and confirm.
/// The caller owns biometric gating and the actual `enableRescue` call —
/// this sheet only gathers the key selection.
///
/// Surfaces Hetzner's caveat prominently: enabling rescue only *arms* it;
/// the server must be rebooted to actually enter the rescue system. The
/// caller offers a chained "Reboot Now" from the result sheet.
struct EnableRescueSheet: View {
    let serverName: String
    let sshKeys: [SSHKey]
    let sshKeysState: ServerDetailViewModel.LoadState
    var onEnable: ([Int]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedKeyIDs: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            HStack(spacing: Spacing.unit * 3) {
                SheetHeaderBadge(systemImage: "lifepreserver")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Rescue Mode")
                        .bodyPrimary()
                        .fontWeight(.semibold)
                    Text(serverName)
                        .caption()
                }
                Spacer()
            }

            keyList

            Text(
                selectedKeyIDs.isEmpty
                    ? "No key selected — you'll get a one-time root password instead, shown exactly once."
                    : "Log in as root with the selected key(s)."
            )
            .caption()
            .fixedSize(horizontal: false, vertical: true)

            Label(
                "The server must be rebooted to enter the rescue system — enabling only arms it for the next boot.",
                systemImage: "exclamationmark.triangle"
            )
            .caption()
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack(spacing: Spacing.unit * 3) {
                Button("Cancel") { dismiss() }
                    .secondaryCTAStyle()
                    .frame(maxWidth: .infinity)

                PrimaryCTA(title: "Enable Rescue Mode") {
                    let ids = selectedKeyIDs.sorted()
                    dismiss()
                    onEnable(ids)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(Spacing.screenMargin)
        .padding(.top, Spacing.unit * 2)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground { CanvasBackground() }
        .presentationCornerRadius(Radius.card)
    }

    @ViewBuilder
    private var keyList: some View {
        switch sshKeysState {
        case .idle, .loading:
            HStack(spacing: Spacing.unit * 2) {
                ProgressView()
                Text("Loading SSH keys…").caption()
            }
        case .failed(let message):
            Text(message).caption()
        case .loaded:
            if sshKeys.isEmpty {
                Text("No SSH keys on this project. You'll get a one-time root password instead.")
                    .bodySecondary()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    GlassCard {
                        VStack(spacing: 0) {
                            ForEach(Array(sshKeys.enumerated()), id: \.element.id) { index, key in
                                if index > 0 {
                                    Divider().overlay(HetzlyColors.textTertiary.opacity(0.2))
                                }
                                keyRow(key)
                            }
                        }
                    }
                }
            }
        }
    }

    private func keyRow(_ key: SSHKey) -> some View {
        Button {
            withAnimation(.snappy) {
                if selectedKeyIDs.contains(key.id) {
                    selectedKeyIDs.remove(key.id)
                } else {
                    selectedKeyIDs.insert(key.id)
                }
            }
        } label: {
            HStack(spacing: Spacing.unit * 3) {
                Image(systemName: selectedKeyIDs.contains(key.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selectedKeyIDs.contains(key.id) ? HetzlyColors.accent : HetzlyColors.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(key.name)
                        .bodyPrimary()
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
    }
}

#Preview {
    ZStack {
        CanvasBackground()
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: .constant(true)) {
        EnableRescueSheet(
            serverName: "hetzi-prod-01",
            sshKeys: [PreviewFixtures.sshKey],
            sshKeysState: .loaded
        ) { _ in }
    }
}
