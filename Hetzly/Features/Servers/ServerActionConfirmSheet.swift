import SwiftUI

/// Confirmation sheet shown before *every* power/lifecycle action fires.
/// Presented at `.height(300)` — `.height(380)` for `.delete`, which adds a
/// "type the server name" field below. The caller (`ServerDetailView`) owns
/// the biometric gating flow for destructive actions — this view is purely
/// presentational: it shows `authError` (with a subtle shake) when the
/// caller reports a failed biometric check, and disables its buttons while
/// `isAuthenticating`.
struct ServerActionConfirmSheet: View {
    let action: PowerAction
    let serverName: String
    var isAuthenticating: Bool = false
    var authError: String?
    var onCancel: () -> Void
    var onConfirm: () -> Void

    @State private var warningTrigger = false
    @State private var shakeCount = 0
    /// Only consulted for `.delete` — see `isDeleteConfirmationSatisfied`.
    @State private var deleteConfirmationText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            header

            Text(action.confirmSubtitle)
                .bodySecondary()
                .fixedSize(horizontal: false, vertical: true)

            if action == .delete {
                deleteConfirmationField
            }

            if let authError {
                Text(authError)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HetzlyColors.destructive)
                    .modifier(ShakeEffect(shakes: CGFloat(shakeCount)))
            }

            Spacer(minLength: 0)

            buttons
        }
        .padding(Spacing.screenMargin)
        .padding(.top, Spacing.unit * 2)
        .presentationDetents([.height(action == .delete ? 380 : 300)])
        .presentationDragIndicator(.visible)
        .presentationBackground { CanvasBackground() }
        .presentationCornerRadius(Radius.card)
        .sensoryFeedback(.warning, trigger: warningTrigger)
        .onAppear {
            if action.isDestructive { warningTrigger.toggle() }
        }
        .onChange(of: authError) { _, newValue in
            guard newValue != nil else { return }
            withAnimation(.snappy) { shakeCount += 1 }
        }
    }

    /// Hardens the most destructive, least reversible action in the app:
    /// deleting a server erases its disks too, so `.delete`'s CTA stays
    /// disabled until the typed text matches `serverName` (case-
    /// insensitive — the point is to force the user to read and confirm the
    /// exact server, not to test their capitalization).
    private var deleteConfirmationField: some View {
        VStack(alignment: .leading, spacing: Spacing.unit) {
            Text("Type the server name to confirm")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(HetzlyColors.textTertiary)
            TextField(
                "",
                text: $deleteConfirmationText,
                prompt: Text(serverName).foregroundStyle(HetzlyColors.textTertiary)
            )
            .font(.system(size: 15, design: .monospaced))
            .foregroundStyle(HetzlyColors.textPrimary)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, Spacing.unit * 3)
            .padding(.vertical, Spacing.unit * 2)
            .background {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            }
            .disabled(isAuthenticating)
            .accessibilityLabel("Type \(serverName) to confirm deletion")
        }
    }

    /// Always `true` for non-`.delete` actions — the field above only
    /// exists (and only gates the CTA) for `.delete`.
    private var isDeleteConfirmationSatisfied: Bool {
        guard action == .delete else { return true }
        let trimmed = deleteConfirmationText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.caseInsensitiveCompare(serverName) == .orderedSame
    }

    private var header: some View {
        HStack(spacing: Spacing.unit * 3) {
            Image(systemName: action.systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(action.isDestructive ? HetzlyColors.destructive : HetzlyColors.accent)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .bodyPrimary()
                    .fontWeight(.semibold)
                Text(serverName)
                    .caption()
            }
            Spacer()
        }
    }

    private var buttons: some View {
        HStack(spacing: Spacing.unit * 3) {
            Button("Cancel", action: onCancel)
                .secondaryCTAStyle()
                .frame(maxWidth: .infinity)
                .disabled(isAuthenticating)

            Group {
                if action.isDestructive {
                    DestructiveCTA(title: confirmTitle, action: onConfirm)
                } else {
                    PrimaryCTA(title: confirmTitle, action: onConfirm)
                }
            }
            .frame(maxWidth: .infinity)
            .disabled(isAuthenticating || !isDeleteConfirmationSatisfied)
        }
    }

    private var confirmTitle: String {
        isAuthenticating ? "Verifying…" : action.confirmButtonTitle
    }
}

/// A small horizontal shake, driven by an incrementing counter so repeated
/// failures re-trigger the animation even if the count value repeats.
private struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = 6 * sin(shakes * .pi * 8)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

#Preview {
    ZStack {
        CanvasBackground()
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: .constant(true)) {
        ServerActionConfirmSheet(
            action: .reset,
            serverName: "hetzi-prod-01",
            authError: "Authentication failed. Try again.",
            onCancel: {},
            onConfirm: {}
        )
    }
}

#Preview("Delete — typed-name gate") {
    ZStack {
        CanvasBackground()
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: .constant(true)) {
        ServerActionConfirmSheet(
            action: .delete,
            serverName: "hetzi-prod-01",
            onCancel: {},
            onConfirm: {}
        )
    }
}
