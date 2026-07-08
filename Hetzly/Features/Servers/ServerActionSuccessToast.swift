import SwiftUI

/// A brief, self-dismissing toast shown right after a power *or*
/// management action completes successfully: a `MascotView(.celebrate)`
/// moment when the mascot is enabled, or plain confirmation text otherwise.
/// Pairs with a `.sensoryFeedback(.success, trigger:)` fired by the caller.
struct ServerActionSuccessToast: View {
    let text: String
    var mascotState: MascotState?
    var mascotEnabled: Bool = true

    /// Power-row convenience initializer. Delete gets a one-shot "hat-tip"
    /// peek instead of the usual celebration — a quieter easter egg for a
    /// destructive win.
    init(kind: PowerAction, mascotEnabled: Bool = true) {
        self.text = Self.successText(for: kind)
        self.mascotState = kind == .delete ? .peek : .celebrate
        self.mascotEnabled = mascotEnabled
    }

    /// General-purpose initializer used by management actions (backups,
    /// rescue, snapshots, rebuild, rescale, ...), which don't share
    /// `PowerAction`'s type but want the same toast treatment.
    init(text: String, mascotState: MascotState? = .celebrate, mascotEnabled: Bool = true) {
        self.text = text
        self.mascotState = mascotState
        self.mascotEnabled = mascotEnabled
    }

    var body: some View {
        HStack(spacing: Spacing.unit * 3) {
            if mascotEnabled, let mascotState {
                MascotView(state: mascotState, scale: 1.5)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(HetzlyColors.statusRunning)
                    .accessibilityHidden(true)
            }
            Text(text)
                .bodySecondary()
        }
        .padding(.horizontal, Spacing.cardPadding)
        .padding(.vertical, Spacing.unit * 3)
        .glassSurface(Capsule(style: .continuous))
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }

    private static func successText(for kind: PowerAction) -> String {
        switch kind {
        case .powerOn: "Server is powered on."
        case .shutdown: "Server shut down cleanly."
        case .reboot: "Server rebooted."
        case .reset: "Server reset."
        case .powerOff: "Server powered off."
        case .delete: "Server deleted."
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        VStack(spacing: Spacing.unit * 4) {
            ServerActionSuccessToast(kind: .reboot, mascotEnabled: true)
            ServerActionSuccessToast(kind: .powerOff, mascotEnabled: false)
            ServerActionSuccessToast(text: "Snapshot created.", mascotEnabled: true)
        }
    }
    .preferredColorScheme(.dark)
}
