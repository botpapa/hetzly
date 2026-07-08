import Foundation

/// One update emitted while polling an `Action` to completion.
///
/// `.failed` carries a `HetznerAPIError`: either the error thrown by the
/// underlying request, or (when the action itself reports `status == .error`)
/// its `code`/`message` re-wrapped as `.api(code:message:)` — this keeps a
/// single, already-`userMessage`-able error type for consumers instead of a
/// second bespoke error enum.
public enum ActionUpdate: Sendable {
    case progress(Action)
    case finished(Action)
    case failed(HetznerAPIError)
    case timedOut
}

/// Polls `CloudClient.action(id:)` until an action finishes, fails, or times
/// out, surfacing each step as an `ActionUpdate` on an `AsyncStream`.
///
/// Polling cadence: every `pollInterval` (default 2s) for the first 30s of
/// real time, then exponential backoff (×1.5, starting at 1.5×`pollInterval`,
/// capped at 5×`pollInterval`) until a 60×`pollInterval` total timeout.
/// `pollInterval` is injectable so tests can run this fast without waiting
/// on real wall-clock seconds; the backoff/timeout thresholds scale with it
/// so the production shape (2s / 30s switch / 3s→10s backoff / 120s timeout)
/// falls out of the default.
public actor ActionTracker {
    private let client: CloudClient
    private let pollInterval: TimeInterval
    private let backoffStart: TimeInterval
    private let backoffCap: TimeInterval
    private let switchToBackoffAfter: TimeInterval
    private let totalTimeout: TimeInterval
    private let clock = ContinuousClock()

    public init(client: CloudClient, pollInterval: TimeInterval = 2.0) {
        self.client = client
        self.pollInterval = pollInterval
        let scale = pollInterval / 2.0
        self.backoffStart = 3.0 * scale
        self.backoffCap = 10.0 * scale
        self.switchToBackoffAfter = 30.0 * scale
        self.totalTimeout = 120.0 * scale
    }

    public func track(actionID: Int) -> AsyncStream<ActionUpdate> {
        AsyncStream { continuation in
            let task = Task {
                await self.runPollLoop(actionID: actionID, continuation: continuation)
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func runPollLoop(actionID: Int, continuation: AsyncStream<ActionUpdate>.Continuation) async {
        let start = clock.now
        var currentBackoff = backoffStart

        while true {
            if Task.isCancelled {
                continuation.finish()
                return
            }

            let elapsed = elapsedSeconds(since: start)
            if elapsed >= totalTimeout {
                continuation.yield(.timedOut)
                continuation.finish()
                return
            }

            do {
                let action = try await client.action(id: actionID)
                if Task.isCancelled {
                    continuation.finish()
                    return
                }

                switch action.status {
                case .success:
                    continuation.yield(.finished(action))
                    continuation.finish()
                    return
                case .error:
                    let code = action.error?.code ?? "action_error"
                    let message = action.error?.message ?? "The action failed."
                    continuation.yield(.failed(.api(code: code, message: message)))
                    continuation.finish()
                    return
                case .running, .unknown:
                    continuation.yield(.progress(action))
                }
            } catch {
                let apiError = error as? HetznerAPIError ?? .transport(underlying: String(describing: error))
                continuation.yield(.failed(apiError))
                continuation.finish()
                return
            }

            let sleepInterval: TimeInterval
            if elapsed >= switchToBackoffAfter {
                sleepInterval = currentBackoff
                currentBackoff = min(currentBackoff * 1.5, backoffCap)
            } else {
                sleepInterval = pollInterval
            }

            try? await clock.sleep(for: Self.duration(fromSeconds: sleepInterval))
        }
    }

    private func elapsedSeconds(since instant: ContinuousClock.Instant) -> TimeInterval {
        let elapsed = clock.now - instant
        let components = elapsed.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    private static func duration(fromSeconds seconds: TimeInterval) -> Duration {
        let clamped = max(0, seconds)
        let wholeSeconds = Int64(clamped)
        let fractional = clamped - Double(wholeSeconds)
        let attoseconds = Int64(fractional * 1_000_000_000_000_000_000)
        return Duration(secondsComponent: wholeSeconds, attosecondsComponent: attoseconds)
    }
}
