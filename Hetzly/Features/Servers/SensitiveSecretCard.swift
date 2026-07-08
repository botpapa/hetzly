import SwiftUI

/// Reusable "reveal once" card for short-lived secrets returned by the API:
/// rescue/reset root passwords, console passwords. Masked by default,
/// tap-to-reveal, copy-with-60s-expiry via `SensitivePasteboard`.
///
/// Reused by the rescue-mode-enable result, reset-root-password result, the
/// console-credentials sheet, and (implicitly, via the same pattern) the
/// rebuild/create-snapshot flows whenever they surface a secret. Never logs
/// `secret` and never persists it beyond this view's own state.
struct SensitiveSecretCard: View {
    let title: String
    let secret: String
    var note: String = "Shown once. Hetzner does not store this password — save it now."

    @State private var isRevealed = false
    @State private var didCopy = false
    @State private var copyHaptic = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                HStack(spacing: Spacing.unit * 2) {
                    Image(systemName: "eye.trianglebadge.exclamationmark")
                        .foregroundStyle(HetzlyColors.accent)
                    Text(title)
                        .bodyPrimary()
                        .fontWeight(.semibold)
                    Spacer()
                }

                revealField

                Button(action: copy) {
                    Label(didCopy ? "Copied — clears in 60s" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .secondaryCTAStyle()

                Text(note)
                    .caption()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: copyHaptic)
    }

    private var revealField: some View {
        Button(action: { withAnimation(.snappy) { isRevealed.toggle() } }) {
            HStack {
                Text(isRevealed ? secret : String(repeating: "•", count: max(10, secret.count)))
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(HetzlyColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
            .padding(.horizontal, Spacing.unit * 3)
            .padding(.vertical, Spacing.unit * 3)
            .background {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRevealed ? "Hide secret" : "Reveal secret")
    }

    private func copy() {
        SensitivePasteboard.copy(secret, expiresIn: 60)
        copyHaptic.toggle()
        withAnimation(.snappy) { didCopy = true }
        Task {
            try? await Task.sleep(for: .seconds(60))
            withAnimation(.snappy) { didCopy = false }
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        VStack(spacing: Spacing.unit * 4) {
            SensitiveSecretCard(
                title: "Rescue Root Password",
                secret: "aB3!xK9zQmP2",
                note: "Shown once. Reboot the server to actually enter rescue mode."
            )
            SensitiveSecretCard(title: "New Root Password", secret: "hV7#wD2nR8sT")
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
