import SwiftUI

/// A brief, self-dismissing toast shown right after a power action
/// completes successfully: a `MascotView(.celebrate)` moment when the
/// mascot is enabled, or plain confirmation text otherwise. Pairs with a
/// `.sensoryFeedback(.success, trigger:)` fired by the caller.
struct ServerActionSuccessToast: View {
    let kind: PowerAction
    var mascotEnabled: Bool = true

    var body: some View {
        HStack(spacing: Spacing.unit * 3) {
            if mascotEnabled {
                // Delete gets a one-shot "hat-tip" peek instead of the usual
                // celebration — a quieter easter egg for a destructive win.
                MascotView(state: kind == .delete ? .peek : .celebrate, scale: 1.5)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(HetzlyColors.statusRunning)
            }
            Text(successText)
                .bodySecondary()
        }
        .padding(.horizontal, Spacing.cardPadding)
        .padding(.vertical, Spacing.unit * 3)
        .glassEffect(.regular, in: .capsule)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var successText: String {
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
        }
    }
    .preferredColorScheme(.dark)
}
