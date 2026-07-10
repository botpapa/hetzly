import XCTest
@testable import Hetzly

/// Reproduces the real-device "endless connecting, then crash on close" report.
///
/// These tests point `SSHConnection` at a LOCAL black-hole TCP server that
/// accepts the connection but never answers the SSH handshake — so the actor
/// stays in `.connecting` exactly like the user's stuck session. We then close
/// it the same ways the UI does (explicit `disconnect()`, cancelling the
/// connect task) and assert the process does not crash.
///
/// Run the black-hole first:
///   python3 scripts/dev/ssh_blackhole.py &   # listens on 127.0.0.1:2222
/// The tests skip themselves (rather than fail) if nothing is listening, so
/// they never break CI where the helper isn't running.
@MainActor
final class SSHConnectionLifecycleTests: XCTestCase {
    private let host = "127.0.0.1"
    private let port = 2222

    private func config() -> SSHConnection.Configuration {
        SSHConnection.Configuration(
            host: host,
            port: port,
            username: "root",
            credential: .password("hunter2")
        )
    }

    private func requireBlackhole() throws {
        // A quick TCP probe; skip if the helper isn't up.
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { throw XCTSkip("no socket") }
        defer { close(sock) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        inet_pton(AF_INET, host, &addr.sin_addr)
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        if !ok { throw XCTSkip("black-hole server not running on \(host):\(port)") }
    }

    /// The core repro: stuck connecting, then the view is dismissed →
    /// `disconnect()`. Must not crash and must end in `.closed`.
    func test_disconnectWhileConnecting_doesNotCrash() async throws {
        try requireBlackhole()
        let connection = SSHConnection()
        let cfg = config()

        // Kick off connect; it will hang in the handshake against the black hole.
        let connectTask = Task { await connection.connect(cfg) }

        // Give it time to reach `.connecting` and start the SSH handshake.
        try await Task.sleep(for: .milliseconds(600))
        let midState = await connection.state
        XCTAssertEqual(midState, .connecting, "expected to be stuck connecting against the black hole")

        // Dismiss — exactly what ServerTerminalView.onDisappear does.
        await connection.disconnect()
        _ = await connectTask.value

        let finalState = await connection.state
        XCTAssertEqual(finalState, .closed)
    }

    /// The cancellation path: the connect task is cancelled while still
    /// connecting (what SwiftUI does when it tears the terminal view's `.task`
    /// down), then disconnected. NIO traps if a promise/EventLoopGroup is
    /// abandoned mid-connect — this asserts we survive that.
    func test_cancelWhileConnecting_doesNotCrash() async throws {
        try requireBlackhole()
        let connection = SSHConnection()
        let cfg = config()

        let connectTask = Task { await connection.connect(cfg) }
        try await Task.sleep(for: .milliseconds(600))
        let midState = await connection.state
        XCTAssertEqual(midState, .connecting)

        // Cancel the connect task the way SwiftUI cancels `.task` on teardown,
        // then explicitly disconnect (the safe path the view's onDisappear
        // takes) so the group is shut down deterministically.
        connectTask.cancel()
        await connection.disconnect()
        _ = await connectTask.value

        let finalState = await connection.state
        XCTAssertEqual(finalState, .closed)
    }

    /// Connect then disconnect twice — teardown must be idempotent (double
    /// `stateContinuation.finish()`, double group shutdown, etc.).
    func test_doubleDisconnect_isIdempotent() async throws {
        try requireBlackhole()
        let connection = SSHConnection()
        let cfg = config()
        let connectTask = Task { await connection.connect(cfg) }
        try await Task.sleep(for: .milliseconds(600))

        await connection.disconnect()
        await connection.disconnect()
        _ = await connectTask.value

        let finalState = await connection.state
        XCTAssertEqual(finalState, .closed)
    }

    /// A refused port (nothing listening) must fail fast to a terminal state,
    /// never hang.
    func test_connectionRefused_goesUnreachable() async throws {
        let connection = SSHConnection()
        var refused = config()
        refused.port = 59_999 // assume nothing is listening here
        await connection.connect(refused)
        let state = await connection.state
        switch state {
        case .unreachable, .authFailed, .closed:
            break // any terminal non-connected state is acceptable
        default:
            XCTFail("expected a terminal failure state, got \(state)")
        }
    }
}
