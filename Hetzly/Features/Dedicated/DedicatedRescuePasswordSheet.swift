import SwiftUI

/// Result sheet shown right after `enableRescue` returns a one-time root
/// password: wraps `SensitiveSecretCard` (reused per the module contract)
/// and offers a chained "Reset Now" — Robot has no direct reboot endpoint,
/// so a software reset (`RobotResetType.sw`) is the equivalent way to
/// actually make the server boot into the armed rescue system.
struct DedicatedRescuePasswordSheet: View {
    let password: String
    var onResetNow: () -> Void
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            SensitiveSecretCard(
                title: "Rescue Root Password",
                secret: password,
                note: "Shown once. Hetzner Robot does not store this password — save it now."
            )

            Spacer(minLength: 0)

            Text("Server must be rebooted to enter rescue — Reset now?")
                .bodySecondary()
                .fixedSize(horizontal: false, vertical: true)

            PrimaryCTA(title: "Reset Now to Enter Rescue") {
                onDone()
                onResetNow()
            }
            .frame(maxWidth: .infinity)

            Button("Done", action: onDone)
                .secondaryCTAStyle()
                .frame(maxWidth: .infinity)
        }
        .padding(Spacing.screenMargin)
        .padding(.top, Spacing.unit * 4)
        .presentationDetents([.height(440)])
        .presentationDragIndicator(.visible)
        .presentationBackground { CanvasBackground() }
        .presentationCornerRadius(Radius.card)
        .interactiveDismissDisabled()
    }
}

#Preview {
    ZStack {
        CanvasBackground()
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: .constant(true)) {
        DedicatedRescuePasswordSheet(password: "aB3!xK9zQmP2", onResetNow: {}, onDone: {})
    }
}
