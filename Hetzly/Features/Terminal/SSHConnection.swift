import Foundation
import NIOCore
import NIOPosix
import NIOSSH

/// Manages one SSH connection + interactive shell session for
/// `ServerTerminalView`.
///
/// An actor because setup is a sequence of async steps — TCP connect → SSH
/// handshake/host-key check/auth (handled internally by `NIOSSHHandler`
/// once it's in the pipeline) → open a `.session` channel → PTY + shell
/// requests — whose result (`state`, the underlying `Channel`s) must not be
/// read or written concurrently from the UI and from NIO's own completion
/// callbacks.
///
/// - Important: swift-nio-ssh's `NIOSSHHandler` is explicitly **not**
///   `Sendable` and its methods (`createChannel`, etc.) are documented as
///   "not thread-safe: may only be called from on the channel [event
///   loop]". `connect()` below is careful to do all `NIOSSHHandler`-touching
///   work inside NIO `EventLoopFuture` combinators (which run on the
///   channel's event loop) and never lets a `NIOSSHHandler` value itself
///   cross into actor-isolated (`await`) code — only `Sendable` types
///   (`Channel`, `Void`) are ever `.get()`-awaited into `self`.
///
/// Byte flow out of the remote shell is exposed as `output`, fed directly
/// from `SSHShellChannelHandler` with no buffering or logging in between.
/// `write(_:)` sends keystrokes; `resize(cols:rows:)` sends an SSH
/// window-change request.
///
/// - Important: This is the ONE feature in Hetzly with third-party
///   dependencies (swift-nio-ssh, SwiftTerm) — see `project.yml`'s
///   `packages:` block for the exception rationale. Nothing in this type
///   ever logs passwords, private key material, or session byte content.
actor SSHConnection {
    struct Configuration: Sendable {
        var host: String
        var port: Int
        var username: String
        var credential: SSHCredential
        var terminalType: String = "xterm-256color"
        var initialCols: Int = 80
        var initialRows: Int = 24
    }

    enum State: Equatable, Sendable {
        case idle
        case connecting
        case connected
        case authFailed
        case unreachable(String)
        case hostKeyMismatch(host: String, expectedFingerprint: String, receivedFingerprint: String)
        case closed
    }

    private(set) var state: State = .idle {
        didSet { stateContinuation.yield(state) }
    }

    /// Raw bytes read from the remote shell, in order.
    nonisolated let output: AsyncStream<[UInt8]>
    private let outputContinuation: AsyncStream<[UInt8]>.Continuation

    /// Every `state` transition, for the view to drive connecting /
    /// connected / error UI reactively.
    nonisolated let stateUpdates: AsyncStream<State>
    private let stateContinuation: AsyncStream<State>.Continuation

    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var rootChannel: Channel?
    private var shellChannel: Channel?

    init() {
        var outputContinuation: AsyncStream<[UInt8]>.Continuation!
        self.output = AsyncStream { outputContinuation = $0 }
        self.outputContinuation = outputContinuation

        var stateContinuation: AsyncStream<State>.Continuation!
        self.stateUpdates = AsyncStream { stateContinuation = $0 }
        self.stateContinuation = stateContinuation
    }

    // MARK: - Connect

    func connect(_ configuration: Configuration) async {
        guard case .idle = state else { return }
        state = .connecting

        // Hard deadline: TCP has its own 10s connect timeout below, but the
        // SSH handshake + auth + shell-open can hang indefinitely if the
        // server drops us mid-auth without failing the pending promise (a
        // real case when a credential is rejected). This independent task
        // guarantees the UI always leaves "connecting" — it tears the
        // connection down after 25s, which also unblocks any hung `.get()`
        // below (the channel closes → the await throws → the catch runs).
        let deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard !Task.isCancelled else { return }
            await self?.failIfStillConnecting()
        }
        defer { deadline.cancel() }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        eventLoopGroup = group

        // nonisolated(unsafe): the concrete auth delegates are internally
        // thread-safe (NSLock-guarded, @unchecked Sendable) — see
        // SSHConnectionAuthDelegates. The existential protocol type isn't
        // Sendable, so this rebinding documents that capturing it in the
        // channelInitializer's @Sendable closure is deliberate and safe.
        nonisolated(unsafe) let authDelegate: NIOSSHClientUserAuthenticationDelegate
        let didExhaustAuthentication: @Sendable () -> Bool
        do {
            (authDelegate, didExhaustAuthentication) = try Self.makeAuthDelegate(configuration: configuration)
        } catch {
            state = .unreachable("Stored SSH key couldn't be read (\(error.localizedDescription)).")
            try? await group.shutdownGracefully()
            eventLoopGroup = nil
            return
        }

        let hostKeyDelegate = SSHTrustOnFirstUseHostKeyDelegate(host: configuration.host, port: configuration.port)
        let outputContinuation = self.outputContinuation
        let onShellClosed: @Sendable (Error?) -> Void = { [weak self] _ in
            Task { await self?.handleShellClosed() }
        }

        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
            .connectTimeout(.seconds(10))
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let sshHandler = NIOSSHHandler(
                        role: .client(.init(userAuthDelegate: authDelegate, serverAuthDelegate: hostKeyDelegate)),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil
                    )
                    try channel.pipeline.syncOperations.addHandler(sshHandler)
                }
            }

        do {
            let connectedChannel = try await bootstrap.connect(host: configuration.host, port: configuration.port).get()

            // The view may have been dismissed while the TCP connect was in
            // flight — `disconnect()` would have run teardown and shut the
            // event-loop group down. Don't keep building on a torn-down
            // connection; close this channel and bail cleanly.
            guard case .connecting = state else {
                try? await connectedChannel.close().get()
                return
            }
            rootChannel = connectedChannel

            // Everything from here down runs as one NIO future chain on
            // `connectedChannel`'s event loop, so it's safe to touch the
            // (non-Sendable) `NIOSSHHandler` — only the final `Channel`
            // (Sendable) crosses back into actor-isolated code via `.get()`.
            let openedShellChannel = try await connectedChannel.pipeline.handler(type: NIOSSHHandler.self)
                .flatMap { sshHandler -> EventLoopFuture<Channel> in
                    let childChannelPromise = connectedChannel.eventLoop.makePromise(of: Channel.self)
                    let readyPromise = connectedChannel.eventLoop.makePromise(of: Void.self)

                    sshHandler.createChannel(childChannelPromise) { childChannel, channelType in
                        guard channelType == .session else {
                            return childChannel.eventLoop.makeFailedFuture(SSHConnectionError.unexpectedChannelType)
                        }
                        return childChannel.eventLoop.makeCompletedFuture {
                            let ioHandler = SSHShellChannelHandler(
                                term: configuration.terminalType,
                                initialCols: configuration.initialCols,
                                initialRows: configuration.initialRows,
                                readyPromise: readyPromise,
                                onOutput: { bytes in outputContinuation.yield(bytes) },
                                onClose: onShellClosed
                            )
                            try childChannel.pipeline.syncOperations.addHandler(ioHandler)
                        }
                    }

                    return childChannelPromise.futureResult.flatMap { childChannel in
                        readyPromise.futureResult.map { childChannel }
                    }
                }.get()

            shellChannel = openedShellChannel

            // If something else (e.g. the view being dismissed mid-connect)
            // already tore this down, don't stomp back to `.connected`.
            guard case .connecting = state else { return }
            state = .connected
        } catch {
            await fail(with: error, hostKeyDelegate: hostKeyDelegate, didExhaustAuthentication: didExhaustAuthentication)
        }
    }

    private static func makeAuthDelegate(
        configuration: Configuration
    ) throws -> (NIOSSHClientUserAuthenticationDelegate, @Sendable () -> Bool) {
        switch configuration.credential {
        case .password(let password):
            let delegate = SSHPasswordAuthDelegate(username: configuration.username, password: password)
            return (delegate, { delegate.didExhaustAuthentication })
        case .privateKeyPEM(let pem):
            let privateKey = try SSHEd25519KeyImporter.importPrivateKey(fromOpenSSHPEM: pem)
            let delegate = SSHPrivateKeyAuthDelegate(username: configuration.username, privateKey: privateKey)
            return (delegate, { delegate.didExhaustAuthentication })
        }
    }

    /// Called by the connect deadline. If the handshake is still pending,
    /// surface a timeout and tear down (which unblocks the hung await).
    private func failIfStillConnecting() async {
        guard case .connecting = state else { return }
        state = .unreachable(
            "Couldn't establish the SSH session in time. Check the server is reachable on port 22, "
                + "and that your SSH key is installed on it (Hetzner servers usually don't accept password login)."
        )
        await teardown()
    }

    private func fail(
        with error: Error,
        hostKeyDelegate: SSHTrustOnFirstUseHostKeyDelegate,
        didExhaustAuthentication: @Sendable () -> Bool
    ) async {
        // The deadline may have already set a terminal state and torn down —
        // don't overwrite its message with a generic one.
        guard case .connecting = state else { return }
        if let mismatch = hostKeyDelegate.mismatch {
            state = .hostKeyMismatch(
                host: hostKeyDelegate.host,
                expectedFingerprint: mismatch.expected,
                receivedFingerprint: mismatch.received
            )
        } else if didExhaustAuthentication() {
            state = .authFailed
        } else {
            state = .unreachable(Self.describe(error))
        }
        await teardown()
    }

    private static func describe(_ error: Error) -> String {
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
            return description
        }
        return String(describing: error)
    }

    private func handleShellClosed() async {
        guard case .connected = state else { return }
        state = .closed
        await teardown()
    }

    // MARK: - I/O

    /// Sends keystrokes/pasted text to the remote shell.
    func write(_ bytes: [UInt8]) async {
        guard let shellChannel else { return }
        var buffer = shellChannel.allocator.buffer(capacity: bytes.count)
        buffer.writeBytes(bytes)
        try? await shellChannel.writeAndFlush(buffer).get()
    }

    /// Notifies the remote PTY of a terminal size change.
    func resize(cols: Int, rows: Int) async {
        guard let shellChannel, cols > 0, rows > 0 else { return }
        let event = SSHChannelRequestEvent.WindowChangeRequest(
            terminalCharacterWidth: cols,
            terminalRowHeight: rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0
        )
        try? await shellChannel.triggerUserOutboundEvent(event).get()
    }

    // MARK: - Teardown

    /// Tears the connection down. Safe to call from any state, including
    /// before `connect()` finishes (e.g. the view was dismissed while still
    /// connecting) — idempotent.
    func disconnect() async {
        guard state != .closed else { return }
        state = .closed
        await teardown()
    }

    private func teardown() async {
        if let rootChannel, rootChannel.isActive {
            try? await rootChannel.close().get()
        }
        rootChannel = nil
        shellChannel = nil
        outputContinuation.finish()
        stateContinuation.finish()

        if let eventLoopGroup {
            try? await eventLoopGroup.shutdownGracefully()
        }
        eventLoopGroup = nil
    }

    deinit {
        // NIO traps ("EventLoopGroup was not shut down") if a
        // MultiThreadedEventLoopGroup is deallocated without being shut
        // down first. Normal teardown() nils this out, but if the view is
        // dismissed mid-connect and the actor is released before the
        // disconnect task finishes, this non-blocking callback shutdown is
        // the safety net that keeps the app from crashing on close.
        eventLoopGroup?.shutdownGracefully { _ in }
    }
}

/// Errors internal to `SSHConnection`'s setup. Never surfaced verbatim to
/// the UI — `ServerTerminalView` only ever sees `SSHConnection.State`.
enum SSHConnectionError: Error, Sendable, LocalizedError {
    case unexpectedChannelType
    case shellSetupRejected
    case channelClosed
    case hostKeyMismatch(host: String, expected: String, received: String)

    var errorDescription: String? {
        switch self {
        case .unexpectedChannelType:
            return "Unexpected SSH channel type."
        case .shellSetupRejected:
            return "The server rejected the shell request."
        case .channelClosed:
            return "The SSH channel closed."
        case .hostKeyMismatch:
            return "The server's host key doesn't match what was trusted before."
        }
    }
}
