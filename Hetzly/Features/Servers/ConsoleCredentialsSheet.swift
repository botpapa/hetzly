import SwiftUI

/// Result sheet for `requestConsole`: the wss URL and one-time VNC password
/// as sensitive cards with expiring copy, plus an honest note that the
/// in-app console isn't built yet.
struct ConsoleCredentialsSheet: View {
    let credentials: ServerDetailViewModel.ConsoleCredentials
    var onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.unit * 4) {
                HStack(spacing: Spacing.unit * 3) {
                    Image(systemName: "terminal")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(HetzlyColors.accent)
                        .frame(width: 36, height: 36)
                    Text("Console Session")
                        .bodyPrimary()
                        .fontWeight(.semibold)
                    Spacer()
                }

                SensitiveSecretCard(
                    title: "Console URL",
                    secret: credentials.wssURL.absoluteString,
                    note: "WebSocket VNC endpoint — valid for a short time only."
                )

                SensitiveSecretCard(
                    title: "Console Password",
                    secret: credentials.password,
                    note: "One-time VNC password for this session."
                )

                Text("Use these with a VNC client that speaks VNC-over-websocket (e.g. noVNC). An in-app console is on the roadmap.")
                    .caption()
                    .fixedSize(horizontal: false, vertical: true)

                Button("Done", action: onDone)
                    .secondaryCTAStyle()
                    .frame(maxWidth: .infinity)
            }
            .padding(Spacing.screenMargin)
            .padding(.top, Spacing.unit * 4)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground { CanvasBackground() }
        .presentationCornerRadius(Radius.card)
    }
}

#Preview {
    ZStack {
        CanvasBackground()
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: .constant(true)) {
        ConsoleCredentialsSheet(
            credentials: .init(
                wssURL: URL(string: "wss://console.hetzner.cloud/?server_id=42&token=abc") ?? URL(fileURLWithPath: "/"),
                password: "vNc9!pQ2xR"
            ),
            onDone: {}
        )
    }
}
