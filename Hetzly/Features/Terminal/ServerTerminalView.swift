import SwiftUI

/// In-app SSH terminal. Binding entry point per `CONTRACTS.md` → "Server-page
/// wave contracts → Terminal module (SP1)" — worker SP2 presents this as a
/// full-screen cover from the server detail Control tab.
///
/// Connects via `SSHConnection` (swift-nio-ssh) as soon as it appears, pipes
/// the shell's byte stream through `SwiftTermBridge` (SwiftTerm), and
/// disconnects the moment it's dismissed — there is no "connect in the
/// background while I look at something else" mode. Each connection phase
/// (`SSHConnection.State`) gets its own full-screen state with plain-language
/// copy; `.unreachable`/`.closed` offer Retry, `.hostKeyMismatch` offers an
/// explicit "trust the new key" action instead of a blind retry, and
/// `.authFailed` explains the credential problem without a same-input retry
/// (retrying the identical rejected credential isn't a useful action).
///
/// - Important: This is the ONE feature in Hetzly with third-party
///   dependencies (swift-nio-ssh + SwiftTerm — see `project.yml`'s
///   `packages:` block for the exception the user explicitly approved).
///   Nothing on this screen ever logs the password/key material passed in
///   via `credential`, or any byte of the session itself.
struct ServerTerminalView: View {
    let host: String
    let port: Int
    let username: String
    let credential: SSHCredential
    let serverName: String

    init(
        host: String,
        port: Int = 22,
        username: String = "root",
        credential: SSHCredential,
        serverName: String
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.credential = credential
        self.serverName = serverName
    }

    @Environment(\.dismiss) private var dismiss

    @State private var connection = SSHConnection()
    @State private var state: SSHConnection.State = .idle
    @State private var connectionAttempt = 0

    private var configuration: SSHConnection.Configuration {
        SSHConnection.Configuration(host: host, port: port, username: username, credential: credential)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if case .connected = state {
                SwiftTermBridge(connection: connection)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                nonConnectedContent
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                statusLine
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task(id: connectionAttempt) {
            await connection.connect(configuration)
        }
        .task(id: connectionAttempt) {
            for await newState in connection.stateUpdates {
                state = newState
            }
        }
        .onDisappear {
            let connection = connection
            Task { await connection.disconnect() }
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(serverName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("\(username)@\(host)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.unit * 2)
        .padding(.bottom, Spacing.unit * 2)
    }

    private var statusLine: some View {
        Text(statusLineText)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.white.opacity(0.4))
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.bottom, Spacing.unit * 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusLineText: String {
        switch state {
        case .idle, .connecting:
            return "connecting to \(username)@\(host):\(port)…"
        case .connected:
            return "connected — \(username)@\(host):\(port)"
        case .authFailed:
            return "authentication failed — \(username)@\(host):\(port)"
        case .unreachable:
            return "unreachable — \(host):\(port)"
        case .hostKeyMismatch:
            return "host key mismatch — \(host):\(port)"
        case .closed:
            return "connection closed — \(username)@\(host):\(port)"
        }
    }

    // MARK: - Non-connected states

    @ViewBuilder
    private var nonConnectedContent: some View {
        VStack {
            Spacer()
            switch state {
            case .idle, .connecting:
                connectingCard
            case .authFailed:
                authFailedCard
            case .unreachable(let reason):
                unreachableCard(reason: reason)
            case .hostKeyMismatch(_, let expected, let received):
                hostKeyMismatchCard(expected: expected, received: received)
            case .closed:
                closedCard
            case .connected:
                EmptyView()
            }
            Spacer()
        }
        .padding(Spacing.screenMargin)
    }

    private var connectingCard: some View {
        VStack(spacing: Spacing.unit * 4) {
            ProgressView()
                .tint(.white)
                .controlSize(.large)
            VStack(spacing: Spacing.unit) {
                Text("Connecting…")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text("\(username)@\(host):\(port)")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var authFailedCard: some View {
        statusCard(
            systemImage: "key.slash.fill",
            tint: HetzlyColors.destructive,
            title: "Authentication Failed",
            message: "The server rejected the credential used to connect as \(username). "
                + "Check the stored SSH key or root password for this server in Credentials, then reopen the terminal."
        ) {
            Button("Close") { dismiss() }
                .secondaryCTAStyle()
        }
    }

    private func unreachableCard(reason: String) -> some View {
        statusCard(
            systemImage: "wifi.slash",
            tint: HetzlyColors.destructive,
            title: "Couldn't Connect",
            message: "Couldn't reach \(host):\(port). \(reason)"
        ) {
            PrimaryCTA(title: "Retry") { retry() }
            Button("Close") { dismiss() }
                .secondaryCTAStyle()
        }
    }

    private func hostKeyMismatchCard(expected: String, received: String) -> some View {
        statusCard(
            systemImage: "exclamationmark.shield.fill",
            tint: HetzlyColors.destructive,
            title: "Host Key Changed",
            message: "The SSH host key \(host) presented doesn't match the one trusted before. "
                + "This can happen after a legitimate server reinstall — but it's also what a "
                + "man-in-the-middle attack looks like. Only continue if you're sure."
        ) {
            VStack(alignment: .leading, spacing: Spacing.unit) {
                fingerprintRow(label: "Trusted", fingerprint: expected)
                fingerprintRow(label: "Received", fingerprint: received)
            }
            .padding(.bottom, Spacing.unit * 2)

            DestructiveCTA(title: "Trust New Key & Reconnect") {
                trustNewHostKeyAndRetry(received: received)
            }

            Button("Close") { dismiss() }
                .secondaryCTAStyle()
        }
    }

    private var closedCard: some View {
        statusCard(
            systemImage: "bolt.horizontal.circle.fill",
            tint: HetzlyColors.textSecondary,
            title: "Connection Closed",
            message: "The SSH session to \(host) ended."
        ) {
            PrimaryCTA(title: "Reconnect") { retry() }
            Button("Close") { dismiss() }
                .secondaryCTAStyle()
        }
    }

    private func fingerprintRow(label: String, fingerprint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
            Text(fingerprint)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .textSelection(.enabled)
        }
    }

    private func statusCard<Actions: View>(
        systemImage: String,
        tint: Color,
        title: String,
        message: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: Spacing.unit * 4) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(tint)

            VStack(spacing: Spacing.unit * 2) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: Spacing.unit * 2) {
                actions()
            }
        }
        .padding(Spacing.cardPadding * 1.5)
        .frame(maxWidth: 360)
    }

    // MARK: - Actions

    private func retry() {
        // Tear the previous connection down explicitly before replacing it.
        // Dropping the reference alone would abandon its event-loop group
        // mid-connect and rely on `SSHConnection.deinit`'s best-effort
        // shutdown — the exact fragile path we don't want on the hot retry
        // loop. `disconnect()` is idempotent and safe from any state.
        let previous = connection
        Task { await previous.disconnect() }
        connection = SSHConnection()
        state = .idle
        connectionAttempt += 1
    }

    private func trustNewHostKeyAndRetry(received: String) {
        SSHHostKeyStore.updateTrustedFingerprint(received, host: host, port: port)
        retry()
    }
}

#Preview("Connecting") {
    ServerTerminalView(
        host: "203.0.113.42",
        credential: .password("preview-only"),
        serverName: "web-01"
    )
    .preferredColorScheme(.dark)
}
