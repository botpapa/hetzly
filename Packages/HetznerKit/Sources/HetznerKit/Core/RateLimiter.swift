import Foundation

/// A simple fixed-window token-bucket rate limiter.
///
/// `waitForSlot()` suspends the caller when the current window's budget is
/// exhausted, resuming once a fresh window starts. `record(response:)` reads
/// Hetzner's `RateLimit-*` response headers to tighten the remaining count,
/// and on a 429 response blocks all future slots until the server-provided
/// reset time.
public actor RateLimiter {
    private let budget: Int
    private let window: TimeInterval
    private let clock = ContinuousClock()

    private var remaining: Int
    private var windowStart: ContinuousClock.Instant
    private var blockedUntil: ContinuousClock.Instant?

    /// - Parameters:
    ///   - budget: number of requests permitted per window.
    ///   - window: window length in seconds.
    public init(budget: Int, window: TimeInterval) {
        self.budget = budget
        self.window = window
        self.remaining = budget
        self.windowStart = ContinuousClock.now
    }

    /// Suspends until a slot is available, then reserves it.
    public func waitForSlot() async {
        if let deadline = blockedUntil {
            if clock.now < deadline {
                try? await clock.sleep(until: deadline)
            }
            blockedUntil = nil
            resetWindow()
        }

        rollWindowIfElapsed()

        while remaining <= 0 {
            let windowEnd = windowStart.advanced(by: Self.duration(fromSeconds: window))
            if clock.now < windowEnd {
                try? await clock.sleep(until: windowEnd)
            }
            rollWindowIfElapsed()
            if remaining <= 0 {
                // Window advanced but header-driven throttling still reports
                // zero remaining; force a reset so we don't spin forever.
                resetWindow()
            }
        }

        remaining -= 1
    }

    /// Reconciles state with the server's view after a response is received.
    public func record(response: HTTPURLResponse) {
        if let remainingHeader = response.value(forHTTPHeaderField: "RateLimit-Remaining"),
           let remainingValue = Int(remainingHeader) {
            remaining = min(remaining, remainingValue)
        }

        guard response.statusCode == 429 else { return }

        if let resetHeader = response.value(forHTTPHeaderField: "RateLimit-Reset"),
           let resetEpoch = TimeInterval(resetHeader) {
            let secondsFromNow = resetEpoch - Date().timeIntervalSince1970
            blockedUntil = clock.now.advanced(by: Self.duration(fromSeconds: max(0, secondsFromNow)))
        } else if let retryAfterHeader = response.value(forHTTPHeaderField: "Retry-After"),
                  let retryAfterSeconds = TimeInterval(retryAfterHeader) {
            blockedUntil = clock.now.advanced(by: Self.duration(fromSeconds: max(0, retryAfterSeconds)))
        } else {
            blockedUntil = clock.now.advanced(by: Self.duration(fromSeconds: window))
        }
        remaining = 0
    }

    private func rollWindowIfElapsed() {
        let windowEnd = windowStart.advanced(by: Self.duration(fromSeconds: window))
        if clock.now >= windowEnd {
            resetWindow()
        }
    }

    private func resetWindow() {
        windowStart = clock.now
        remaining = budget
    }

    private static func duration(fromSeconds seconds: TimeInterval) -> Duration {
        let clamped = max(0, seconds)
        let wholeSeconds = Int64(clamped)
        let fractional = clamped - Double(wholeSeconds)
        let attoseconds = Int64(fractional * 1_000_000_000_000_000_000)
        return Duration(secondsComponent: wholeSeconds, attosecondsComponent: attoseconds)
    }
}
