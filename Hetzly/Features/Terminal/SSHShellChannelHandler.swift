import NIOCore
import NIOSSH

/// Drives the SSH session child channel once it's open: requests a PTY, then
/// a shell, then streams raw bytes both ways.
///
/// - `channelActive` fires the `pty-req` and `shell` channel requests
///   (`wantReply: true`) and tracks their `SSH_MSG_CHANNEL_SUCCESS`/
///   `SSH_MSG_CHANNEL_FAILURE` replies (matched FIFO — the SSH RFCs don't
///   guarantee ordering in general, but in practice, and per every server
///   implementation in wide use, replies to sequential requests on one
///   channel come back in the order the requests were sent) via
///   `readyPromise`, which `SSHConnection.connect` awaits to know the shell
///   is actually usable before reporting `.connected`.
/// - Inbound `SSHChannelData` (both `.channel` and `.stdErr`) is handed to
///   `onOutput` as raw bytes — SwiftTerm's parser handles interleaved
///   stdout/stderr the same way a real terminal does, so there's no need to
///   keep them separate.
/// - Outbound `ByteBuffer`s (keystrokes) are wrapped as `SSHChannelData`.
///
/// - Important: `onOutput` is the ONLY place session bytes flow through this
///   type on their way to the UI; nothing here ever logs them.
final class SSHShellChannelHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    private let term: String
    private let initialCols: Int
    private let initialRows: Int
    private let readyPromise: EventLoopPromise<Void>
    private let onOutput: @Sendable ([UInt8]) -> Void
    private let onClose: @Sendable (Error?) -> Void

    /// Promises for in-flight `wantReply: true` channel requests, in the
    /// order they were sent. Only ever touched on this handler's event
    /// loop, so no locking is needed.
    private var pendingRequestPromises: [EventLoopPromise<Void>] = []

    init(
        term: String,
        initialCols: Int,
        initialRows: Int,
        readyPromise: EventLoopPromise<Void>,
        onOutput: @escaping @Sendable ([UInt8]) -> Void,
        onClose: @escaping @Sendable (Error?) -> Void
    ) {
        self.term = term
        self.initialCols = initialCols
        self.initialRows = initialRows
        self.readyPromise = readyPromise
        self.onOutput = onOutput
        self.onClose = onClose
    }

    func handlerAdded(context: ChannelHandlerContext) {
        context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).whenFailure { _ in
            // Not fatal — half-closure just won't be permitted. Nothing to
            // recover from here.
        }
    }

    func channelActive(context: ChannelHandlerContext) {
        context.fireChannelActive()

        let ptyPromise = context.eventLoop.makePromise(of: Void.self)
        let shellPromise = context.eventLoop.makePromise(of: Void.self)
        pendingRequestPromises = [ptyPromise, shellPromise]

        ptyPromise.futureResult
            .flatMap { shellPromise.futureResult }
            .cascade(to: readyPromise)

        let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: term,
            terminalCharacterWidth: max(initialCols, 1),
            terminalRowHeight: max(initialRows, 1),
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([:])
        )
        context.triggerUserOutboundEvent(ptyRequest, promise: nil)

        let shellRequest = SSHChannelRequestEvent.ShellRequest(wantReply: true)
        context.triggerUserOutboundEvent(shellRequest, promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard case .byteBuffer(var buffer) = channelData.data else { return }
        guard let bytes = buffer.readBytes(length: buffer.readableBytes), !bytes.isEmpty else { return }
        onOutput(bytes)
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case is ChannelSuccessEvent:
            if !pendingRequestPromises.isEmpty {
                pendingRequestPromises.removeFirst().succeed(())
            }
        case is ChannelFailureEvent:
            if !pendingRequestPromises.isEmpty {
                pendingRequestPromises.removeFirst().fail(SSHConnectionError.shellSetupRejected)
            }
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        failPendingPromises(with: SSHConnectionError.channelClosed)
        onClose(nil)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        failPendingPromises(with: error)
        onClose(error)
        context.fireErrorCaught(error)
    }

    private func failPendingPromises(with error: Error) {
        let promises = pendingRequestPromises
        pendingRequestPromises = []
        for promise in promises {
            promise.fail(error)
        }
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = unwrapOutboundIn(data)
        context.write(wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(buffer))), promise: promise)
    }
}
