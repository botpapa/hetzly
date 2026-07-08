import HetznerKit
import SwiftUI

/// Sheet for enabling rescue mode on a dedicated server: pick an OS from the
/// distributions Robot's boot configuration reports as available, then
/// multi-select the account's SSH keys (or none, in which case Robot issues
/// a one-time root password). Mirrors `EnableRescueSheet` for the Cloud
/// side; the caller owns biometric gating and the actual `enableRescue`
/// call.
struct EnableDedicatedRescueSheet: View {
    let serverName: String
    let osOptions: [String]
    let sshKeys: [RobotSSHKey]
    let sshKeysState: DedicatedServerDetailViewModel.LoadState
    /// `(os, sshKeyFingerprints)`.
    var onEnable: (String, [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedOS: String?
    @State private var selectedFingerprints: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            header

            osPicker

            keyList

            Text(
                selectedFingerprints.isEmpty
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
                    guard let selectedOS else { return }
                    let fingerprints = Array(selectedFingerprints)
                    dismiss()
                    onEnable(selectedOS, fingerprints)
                }
                .frame(maxWidth: .infinity)
                .disabled(selectedOS == nil)
            }
        }
        .padding(Spacing.screenMargin)
        .padding(.top, Spacing.unit * 2)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground { CanvasBackground() }
        .presentationCornerRadius(Radius.card)
        .onAppear {
            if selectedOS == nil { selectedOS = osOptions.first }
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.unit * 3) {
            Image(systemName: "lifepreserver")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(HetzlyColors.accent)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Enable Rescue Mode")
                    .bodyPrimary()
                    .fontWeight(.semibold)
                Text(serverName)
                    .caption()
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var osPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Operating System")
            if osOptions.isEmpty {
                Text("No rescue distributions are available for this server right now.")
                    .bodySecondary()
            } else {
                GlassCard {
                    VStack(spacing: 0) {
                        ForEach(Array(osOptions.enumerated()), id: \.element) { index, os in
                            if index > 0 {
                                Divider().overlay(HetzlyColors.textTertiary.opacity(0.2))
                            }
                            osRow(os)
                        }
                    }
                }
            }
        }
    }

    private func osRow(_ os: String) -> some View {
        Button {
            withAnimation(.snappy) { selectedOS = os }
        } label: {
            HStack(spacing: Spacing.unit * 3) {
                Image(systemName: selectedOS == os ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selectedOS == os ? HetzlyColors.accent : HetzlyColors.textTertiary)
                Text(os).bodyPrimary()
                Spacer()
            }
            .padding(.vertical, Spacing.unit * 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var keyList: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("SSH Keys")
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
                    Text("No SSH keys on this account. You'll get a one-time root password instead.")
                        .bodySecondary()
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    GlassCard {
                        VStack(spacing: 0) {
                            ForEach(Array(sshKeys.enumerated()), id: \.element.fingerprint) { index, key in
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

    private func keyRow(_ key: RobotSSHKey) -> some View {
        Button {
            withAnimation(.snappy) {
                if selectedFingerprints.contains(key.fingerprint) {
                    selectedFingerprints.remove(key.fingerprint)
                } else {
                    selectedFingerprints.insert(key.fingerprint)
                }
            }
        } label: {
            HStack(spacing: Spacing.unit * 3) {
                Image(systemName: selectedFingerprints.contains(key.fingerprint) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selectedFingerprints.contains(key.fingerprint) ? HetzlyColors.accent : HetzlyColors.textTertiary)
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
        EnableDedicatedRescueSheet(
            serverName: "AX101 #12345",
            osOptions: ["linux", "linuxold", "vkvm"],
            sshKeys: [DedicatedPreviewFixtures.sshKey],
            sshKeysState: .loaded
        ) { _, _ in }
    }
}
