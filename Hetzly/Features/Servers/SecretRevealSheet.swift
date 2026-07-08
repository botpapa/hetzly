import SwiftUI

/// Result sheet for management actions that return a one-time secret
/// (rescue password, reset root password, rebuild root password): wraps
/// `SensitiveSecretCard` and — for rescue — offers the chained "Reboot Now"
/// so the user can actually enter the rescue system without hunting for the
/// reboot button afterwards.
struct SecretRevealSheet: View {
    let secret: ServerDetailViewModel.RevealedSecret
    var onReboot: (() -> Void)?
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            SensitiveSecretCard(
                title: secret.title,
                secret: secret.secret,
                note: secret.note
            )

            Spacer(minLength: 0)

            if secret.offersReboot, let onReboot {
                PrimaryCTA(title: "Reboot Now to Enter Rescue") {
                    onDone()
                    onReboot()
                }
                .frame(maxWidth: .infinity)
            }

            Button("Done", action: onDone)
                .secondaryCTAStyle()
                .frame(maxWidth: .infinity)
        }
        .padding(Spacing.screenMargin)
        .padding(.top, Spacing.unit * 4)
        .presentationDetents([.height(secret.offersReboot ? 400 : 340)])
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
        SecretRevealSheet(
            secret: .init(
                title: "Rescue Root Password",
                secret: "aB3!xK9zQmP2",
                note: "Shown once. Reboot the server to actually enter rescue mode.",
                offersReboot: true
            ),
            onReboot: {},
            onDone: {}
        )
    }
}
