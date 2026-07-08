import Foundation
import Testing
@testable import HetznerKit

@Suite("ActionTracker")
struct CloudAPIActionTrackerTests {
    /// Fast poll interval so these tests don't wait on real wall-clock
    /// seconds; the tracker scales its backoff/timeout thresholds off it.
    private static let testPollInterval: TimeInterval = 0.05

    @Test func runningThenSuccessCompletesTheStream() async throws {
        let transport = MockTransport(responses: [
            .init(statusCode: 200, data: CloudAPIFixtures.actionEnvelopeJSON(id: 1, status: "running", progress: 10)),
            .init(statusCode: 200, data: CloudAPIFixtures.actionEnvelopeJSON(id: 1, status: "running", progress: 60)),
            .init(statusCode: 200, data: CloudAPIFixtures.actionEnvelopeJSON(id: 1, status: "success", progress: 100)),
        ])
        let client = CloudClient(token: "t", transport: transport)
        let tracker = ActionTracker(client: client, pollInterval: Self.testPollInterval)

        var updates: [ActionUpdate] = []
        for await update in await tracker.track(actionID: 1) {
            updates.append(update)
        }

        #expect(updates.count == 3)
        if case .progress(let action) = updates[0] {
            #expect(action.progress == 10)
        } else {
            Issue.record("Expected first update to be .progress")
        }
        if case .progress(let action) = updates[1] {
            #expect(action.progress == 60)
        } else {
            Issue.record("Expected second update to be .progress")
        }
        if case .finished(let action) = updates[2] {
            #expect(action.progress == 100)
            #expect(action.status == .success)
        } else {
            Issue.record("Expected final update to be .finished")
        }
    }

    @Test func actionErrorStatusEmitsFailedAndCompletesTheStream() async throws {
        let transport = MockTransport(responses: [
            .init(
                statusCode: 200,
                data: CloudAPIFixtures.actionEnvelopeJSON(
                    id: 2,
                    status: "error",
                    errorCode: "action_failed",
                    errorMessage: "Something went wrong."
                )
            ),
        ])
        let client = CloudClient(token: "t", transport: transport)
        let tracker = ActionTracker(client: client, pollInterval: Self.testPollInterval)

        var updates: [ActionUpdate] = []
        for await update in await tracker.track(actionID: 2) {
            updates.append(update)
        }

        #expect(updates.count == 1)
        if case .failed(let error) = updates[0], case .api(let code, let message) = error {
            #expect(code == "action_failed")
            #expect(message == "Something went wrong.")
        } else {
            Issue.record("Expected .failed(.api) update")
        }
    }

    @Test func thrownTransportErrorEmitsFailedAndCompletesTheStream() async throws {
        let transport = MockTransport(responses: [
            .init(statusCode: 401, data: Data()),
        ])
        let client = CloudClient(token: "t", transport: transport)
        let tracker = ActionTracker(client: client, pollInterval: Self.testPollInterval)

        var updates: [ActionUpdate] = []
        for await update in await tracker.track(actionID: 3) {
            updates.append(update)
        }

        #expect(updates.count == 1)
        if case .failed(let error) = updates[0] {
            #expect(error.userMessage.contains("token"))
        } else {
            Issue.record("Expected .failed update")
        }
    }

    @Test func consumerCancellationStopsPolling() async throws {
        let transport = MockTransport(responses: Array(
            repeating: .init(statusCode: 200, data: CloudAPIFixtures.actionEnvelopeJSON(id: 4, status: "running")),
            count: 50
        ))
        let client = CloudClient(token: "t", transport: transport)
        let tracker = ActionTracker(client: client, pollInterval: Self.testPollInterval)

        // Iterate the stream inline (rather than binding it to a local `let`)
        // so nothing keeps its underlying storage alive past `break` — that
        // storage's deinit is what fires `onTermination` and cancels the
        // tracker's internal polling task.
        var seen = 0
        for await _ in await tracker.track(actionID: 4) {
            seen += 1
            if seen == 2 { break }
        }

        // Give the stream's onTermination-triggered task cancellation a
        // moment to propagate, then confirm it isn't still consuming
        // responses indefinitely.
        try await Task.sleep(for: .milliseconds(200))
        let requestCountAfterPause = await transport.recordedRequests.count

        try await Task.sleep(for: .milliseconds(200))
        let requestCountLater = await transport.recordedRequests.count

        #expect(requestCountAfterPause == requestCountLater)
    }
}
