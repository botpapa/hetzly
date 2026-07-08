import SwiftTerm
import SwiftUI

/// Wraps SwiftTerm's `TerminalView` (a UIKit terminal emulator) for
/// `ServerTerminalView`, bridging its byte-oriented delegate API to
/// `SSHConnection`'s async stream/actor API.
///
/// - Important: never logs the bytes flowing through it in either
///   direction — `terminalView.feed` and `connection.write` are the only
///   things touching session content here.
struct SwiftTermBridge: UIViewRepresentable {
    let connection: SSHConnection

    func makeUIView(context: Context) -> TerminalView {
        let terminalView = TerminalView(frame: .zero)
        terminalView.backgroundColor = .black
        terminalView.terminalDelegate = context.coordinator
        context.coordinator.attach(terminalView: terminalView)
        return terminalView
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        // Resizing is driven by `TerminalView.layoutSubviews` itself
        // (invoked automatically by UIKit as this view's frame changes
        // under SwiftUI's layout), which calls back through
        // `TerminalViewDelegate.sizeChanged` — no manual work needed here.
    }

    static func dismantleUIView(_ uiView: TerminalView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(connection: connection)
    }

    /// `TerminalView` (a `UIView` subclass) and its delegate callbacks are
    /// only ever touched from the main thread in practice — SwiftUI calls
    /// `makeUIView`/`updateUIView`/`dismantleUIView` on the main actor, and
    /// SwiftTerm itself drives `TerminalViewDelegate` from UIKit event
    /// handling (also main thread). `@unchecked Sendable` reflects that
    /// real, if not statically-enforced-by-SwiftTerm, single-threaded
    /// access pattern; `terminalView`/`outputTask` are only ever mutated
    /// from `attach`/`detach`, which SwiftUI only calls on the main actor.
    final class Coordinator: NSObject, TerminalViewDelegate, @unchecked Sendable {
        private let connection: SSHConnection
        private weak var terminalView: TerminalView?
        private var outputTask: Task<Void, Never>?

        init(connection: SSHConnection) {
            self.connection = connection
        }

        @MainActor
        func attach(terminalView: TerminalView) {
            self.terminalView = terminalView
            outputTask?.cancel()

            let connection = self.connection
            outputTask = Task { @MainActor [weak self] in
                for await bytes in connection.output {
                    guard let self, let terminalView = self.terminalView else { break }
                    terminalView.feed(byteArray: bytes[...])
                }
            }
        }

        func detach() {
            outputTask?.cancel()
            outputTask = nil
        }

        // MARK: - TerminalViewDelegate
        //
        // SwiftTerm invokes these on the main thread (they originate from
        // UIKit input/layout events), but they're declared `nonisolated`
        // here to match the (non-actor-isolated) protocol requirement —
        // each hands straight off to the `SSHConnection` actor.

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            let connection = self.connection
            Task { await connection.resize(cols: newCols, rows: newRows) }
        }

        func setTerminalTitle(source: TerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let bytes = Array(data)
            let connection = self.connection
            Task { await connection.write(bytes) }
        }

        func scrolled(source: TerminalView, position: Double) {}

        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}

        func bell(source: TerminalView) {}

        func clipboardCopy(source: TerminalView, content: Data) {}

        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
