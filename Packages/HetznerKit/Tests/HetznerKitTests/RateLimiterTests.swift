import Foundation
import Testing
@testable import HetznerKit

@Suite("RateLimiter")
struct RateLimiterTests {
    @Test func allowsRequestsUpToBudgetWithoutBlocking() async throws {
        let limiter = RateLimiter(budget: 3, window: 5)
        let start = ContinuousClock.now
        await limiter.waitForSlot()
        await limiter.waitForSlot()
        await limiter.waitForSlot()
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .milliseconds(200))
    }

    @Test func blocksAfterBudgetExhaustedUntilWindowRolls() async throws {
        let window: TimeInterval = 0.3
        let limiter = RateLimiter(budget: 2, window: window)
        await limiter.waitForSlot()
        await limiter.waitForSlot()

        let start = ContinuousClock.now
        await limiter.waitForSlot()
        let elapsed = ContinuousClock.now - start

        #expect(elapsed >= .milliseconds(200))
    }

    @Test func recordWith429DefersFutureSlots() async throws {
        let limiter = RateLimiter(budget: 5, window: 10)
        let resetEpoch = Date().timeIntervalSince1970 + 0.3
        let response = HTTPURLResponse(
            url: URL(string: "https://api.hetzner.cloud/v1/servers")!,
            statusCode: 429,
            httpVersion: "HTTP/1.1",
            headerFields: ["RateLimit-Reset": String(resetEpoch)]
        )!
        await limiter.record(response: response)

        let start = ContinuousClock.now
        await limiter.waitForSlot()
        let elapsed = ContinuousClock.now - start

        #expect(elapsed >= .milliseconds(200))
    }

    @Test func recordUpdatesRemainingFromHeaders() async throws {
        let limiter = RateLimiter(budget: 10, window: 0.3)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.hetzner.cloud/v1/servers")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["RateLimit-Remaining": "0"]
        )!
        await limiter.record(response: response)

        let start = ContinuousClock.now
        await limiter.waitForSlot()
        let elapsed = ContinuousClock.now - start

        // Remaining was clamped to 0 by the header, so this slot must wait
        // for the (short) window to roll over rather than being granted immediately.
        #expect(elapsed >= .milliseconds(50))
    }
}
