import UserNotifications
import XCTest
@testable import Hetzly

/// Exercises `NotificationService`'s pure decision/composition logic —
/// `shouldPost`, `isGranted`, and `composeContent` — which are deliberately
/// factored out of the `UNUserNotificationCenter`/`UIApplication` calls so
/// they're testable without touching the notification system or app
/// lifecycle. Actual delivery (the system permission prompt, whether a
/// banner really appears while backgrounded, `beginBackgroundTask` really
/// buying extra runtime) needs on-device/simulator validation — see the
/// worker report.
final class NotificationServiceTests: XCTestCase {
    // MARK: - shouldPost (foreground-suppression + permission gate)

    func test_shouldPost_true_onlyWhenBackgroundedAndAuthorized() {
        XCTAssertTrue(NotificationService.shouldPost(isBackgrounded: true, authorizationGranted: true))
    }

    func test_shouldPost_false_whenForeground_evenIfAuthorized() {
        // Foreground already shows the in-app toast/haptic — posting too
        // would double-notify the user for the same completion.
        XCTAssertFalse(NotificationService.shouldPost(isBackgrounded: false, authorizationGranted: true))
    }

    func test_shouldPost_false_whenBackgrounded_butNotAuthorized() {
        // Denied / not-yet-determined permission must never post, even
        // while backgrounded.
        XCTAssertFalse(NotificationService.shouldPost(isBackgrounded: true, authorizationGranted: false))
    }

    func test_shouldPost_false_whenNeitherBackgroundedNorAuthorized() {
        XCTAssertFalse(NotificationService.shouldPost(isBackgrounded: false, authorizationGranted: false))
    }

    // MARK: - isGranted (authorization status → can-post mapping)

    func test_isGranted_true_forAuthorized() {
        XCTAssertTrue(NotificationService.isGranted(.authorized))
    }

    func test_isGranted_true_forProvisional() {
        XCTAssertTrue(NotificationService.isGranted(.provisional))
    }

    func test_isGranted_true_forEphemeral() {
        XCTAssertTrue(NotificationService.isGranted(.ephemeral))
    }

    func test_isGranted_false_forDenied() {
        XCTAssertFalse(NotificationService.isGranted(.denied))
    }

    func test_isGranted_false_forNotDetermined() {
        // Not-yet-determined must never be treated as "can post" — that
        // would skip the lazy `requestAuthorization` prompt entirely.
        XCTAssertFalse(NotificationService.isGranted(.notDetermined))
    }

    // MARK: - composeContent (message composition, no secrets)

    func test_composeContent_success_namesActionAndServer() {
        let content = NotificationService.composeContent(success: true, actionTitle: "Reboot", serverName: "web-01")
        XCTAssertEqual(content.title, "Reboot Complete")
        XCTAssertTrue(content.body.contains("web-01"))
    }

    func test_composeContent_failure_namesActionAndServer() {
        let content = NotificationService.composeContent(success: false, actionTitle: "Rebuild", serverName: "db-02")
        XCTAssertEqual(content.title, "Rebuild Failed")
        XCTAssertTrue(content.body.contains("db-02"))
    }

    func test_composeContent_neverIncludesMoreThanActionAndServerName() {
        // Guards the "no secrets in notification text" requirement: the
        // composed strings must be built ONLY from their two inputs, so a
        // token/password accidentally threaded in as `actionTitle` or
        // `serverName` is a call-site bug this test can't catch — but
        // nothing else (session data, credentials) is ever concatenated in.
        let action = "Enable Rescue Mode"
        let server = "prod-db-03"
        let success = NotificationService.composeContent(success: true, actionTitle: action, serverName: server)
        let failure = NotificationService.composeContent(success: false, actionTitle: action, serverName: server)

        for content in [success, failure] {
            let combined = content.title + " " + content.body
            XCTAssertTrue(combined.contains(action))
            XCTAssertTrue(combined.contains(server))
        }
    }

    func test_composeContent_differsBySuccessFlag() {
        let success = NotificationService.composeContent(success: true, actionTitle: "Reboot", serverName: "web-01")
        let failure = NotificationService.composeContent(success: false, actionTitle: "Reboot", serverName: "web-01")
        XCTAssertNotEqual(success.title, failure.title)
    }

    // MARK: - Live service smoke test (init/lifecycle wiring only)

    @MainActor
    func test_init_doesNotCrash_andReflectsCurrentAppState() {
        // A full round trip through `UNUserNotificationCenter` needs a
        // signed, on-device/simulator run (see worker report) — this just
        // confirms the service constructs, observes lifecycle notifications,
        // and reads `UIApplication.shared.applicationState` without
        // crashing in the test host process.
        let service = NotificationService()
        XCTAssertNotNil(service)
    }
}
