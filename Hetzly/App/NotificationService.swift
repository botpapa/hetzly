import Foundation
import UIKit
import UserNotifications

/// Fires a local notification when a tracked long-running server action
/// (reboot/rebuild/rescale/create/snapshot/...) finishes while the app is
/// backgrounded — the "daily driver" ask that fits the no-push-server,
/// no-background-polling design: `ActionTracker` already polls in-process
/// for as long as the app process is alive, so this service just needs to
/// (a) buy a short background-execution extension so an in-flight poll gets
/// a real chance to reach a terminal state after the user backgrounds the
/// app, and (b) post a `UNUserNotificationCenter` local notification on
/// completion — but ONLY when the app is backgrounded, since a foregrounded
/// app already shows the in-app success toast/haptic and notifying too
/// would be a duplicate.
///
/// ## Best-effort background window
/// `notifyOnCompletion` opens a `UIApplication.beginBackgroundTask`
/// reservation that stays open until the matching `finish(_:success:)`
/// call. This grants iOS-controlled extra runtime (historically up to
/// ~30s, never guaranteed) if/when the app backgrounds before the tracked
/// action resolves. If the system revokes the reservation first (the
/// `expirationHandler` fires), the task is ended promptly and the
/// notification simply never fires for that handle — the action still
/// completes server-side, and the user sees the new state next time they
/// open the app. This is the documented, accepted tradeoff: with no push
/// server, there is no way to notify a fully-suspended process.
///
/// ## Permission
/// Authorization is requested lazily — the first time any caller starts a
/// trackable action via `notifyOnCompletion`, not at app launch — so the
/// system prompt appears in context rather than on a cold launch nobody
/// asked for. (`init` does eagerly read, but never prompts for, the
/// *current* authorization status via `notificationSettings()`, so a
/// returning user who already granted permission in an earlier session
/// doesn't have to wait out a fresh round trip on their very first action
/// of this launch.) A denial, a not-yet-determined status, or any request
/// failure all degrade the same way: posting is silently skipped. Nothing
/// about the permission flow ever blocks, delays, or errors out the
/// underlying server action.
@MainActor
final class NotificationService {
    /// A single in-flight tracked action, returned by `notifyOnCompletion`
    /// and resolved exactly once via `finish(_:success:)`. Carries the
    /// `beginBackgroundTask` reservation so ending it happens automatically
    /// alongside firing (or skipping) the notification.
    final class TrackedAction {
        fileprivate let actionTitle: String
        fileprivate let serverName: String
        fileprivate var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        fileprivate var isResolved = false

        fileprivate init(actionTitle: String, serverName: String) {
            self.actionTitle = actionTitle
            self.serverName = serverName
        }
    }

    /// Kept in sync with `UIApplication.didEnterBackgroundNotification` /
    /// `willEnterForegroundNotification` (observed in `init` via async
    /// `NotificationCenter.notifications(named:)` sequences), deliberately
    /// independent of `HetzlyApp`/`RootView`'s `scenePhase` — this service
    /// doesn't touch `Hetzly/App/` entry-point wiring, so it watches app
    /// lifecycle directly instead of needing a relay from the App/RootView
    /// layer.
    private(set) var isBackgrounded: Bool

    private var didRequestAuthorization = false
    private var authorizationGranted = false

    private let center: UNUserNotificationCenter
    // nonisolated(unsafe): written only from the @MainActor init; deinit
    // (nonisolated) may only cancel, which `Task` supports from any
    // context. Mirrors `ServerDetailViewModel.actionTask`'s rationale.
    private nonisolated(unsafe) var lifecycleTasks: [Task<Void, Never>] = []

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        self.isBackgrounded = UIApplication.shared.applicationState == .background
        startObservingLifecycle()
        refreshAuthorizationStatus()
    }

    deinit {
        for task in lifecycleTasks { task.cancel() }
    }

    private func startObservingLifecycle() {
        lifecycleTasks.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.didEnterBackgroundNotification) {
                self?.isBackgrounded = true
            }
        })
        lifecycleTasks.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.willEnterForegroundNotification) {
                self?.isBackgrounded = false
            }
        })
    }

    /// Reads (never prompts for) the current notification authorization
    /// status. Safe to call at launch: `notificationSettings()` never shows
    /// a system prompt, unlike `requestAuthorization` — only the latter,
    /// gated behind `notifyOnCompletion`'s lazy first call, can do that.
    private func refreshAuthorizationStatus() {
        Task { [weak self, center] in
            let settings = await center.notificationSettings()
            guard let self else { return }
            self.authorizationGranted = Self.isGranted(settings.authorizationStatus)
            if settings.authorizationStatus != .notDetermined {
                self.didRequestAuthorization = true
            }
        }
    }

    // MARK: - Begin/finish tracking

    /// Call when a trackable action (power/management/rescale/row action)
    /// starts. Requests notification authorization lazily on the
    /// first-ever call in this process, and opens a `beginBackgroundTask`
    /// reservation so a still-running `ActionTracker` poll loop gets extra
    /// runtime if the app backgrounds before the action resolves. Every
    /// returned handle MUST be resolved exactly once via
    /// `finish(_:success:)`.
    func notifyOnCompletion(actionTitle: String, serverName: String) -> TrackedAction {
        requestAuthorizationIfNeeded()

        let handle = TrackedAction(actionTitle: actionTitle, serverName: serverName)
        handle.backgroundTaskID = UIApplication.shared.beginBackgroundTask(
            withName: "com.hetzly.action-completion"
        ) { [weak handle] in
            // Expiration handler: iOS revoked our extra time before the
            // poll reached a terminal state. Best-effort by design — end
            // the task promptly rather than let the OS force-kill the
            // process; no notification fires for this handle (see the
            // type doc comment's "best-effort background window" note).
            // Dispatched through a `Task` (rather than touching MainActor
            // state directly from this closure) since UIKit does not
            // guarantee which thread invokes this handler, and the closure
            // deliberately captures only `handle` (not `self`) so this
            // keeps working regardless of how strictly the SDK's
            // `expirationHandler` parameter is Sendable-annotated.
            Task { @MainActor in
                guard let handle else { return }
                NotificationService.endBackgroundTaskIfNeeded(handle)
            }
        }
        return handle
    }

    /// Resolves `handle`: posts a local notification if (and only if) the
    /// app is currently backgrounded and authorization was granted, then
    /// ends the background-task reservation. Safe to call at most once per
    /// handle — a second call, or a call after the expiration handler
    /// already fired, is a no-op.
    func finish(_ handle: TrackedAction, success: Bool) {
        guard !handle.isResolved else { return }
        handle.isResolved = true
        fire(success: success, actionTitle: handle.actionTitle, serverName: handle.serverName)
        Self.endBackgroundTaskIfNeeded(handle)
    }

    /// `static` (rather than an instance method) so the `beginBackgroundTask`
    /// expiration handler above can call it while capturing only `handle` —
    /// never `self` — keeping that closure's captures minimal regardless of
    /// its actual Sendable/isolation annotation in the SDK. Guards against
    /// double-ending the same `UIBackgroundTaskIdentifier` (a real crash
    /// risk) whether it's `finish(_:success:)` or the expiration handler
    /// that gets there first: whichever runs first flips `backgroundTaskID`
    /// to `.invalid`, so the other's guard clause makes it a no-op — safe
    /// because both paths are dispatched onto the main actor, which
    /// serializes them.
    private static func endBackgroundTaskIfNeeded(_ handle: TrackedAction) {
        guard handle.backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(handle.backgroundTaskID)
        handle.backgroundTaskID = .invalid
    }

    // MARK: - Posting

    /// Posts a local "<action> complete/failed" notification naming
    /// `serverName`, but only when the app is currently backgrounded (a
    /// foregrounded app already shows the in-app success toast/haptic —
    /// see `Self.shouldPost`) and notification authorization has been
    /// granted. Never throws, never blocks: `center.add` runs
    /// fire-and-forget and its failures are swallowed, since a missed
    /// notification must never surface as an action failure.
    /// `actionTitle`/`serverName` are the only dynamic content in the
    /// notification text — never a token, password, or other secret.
    func fire(success: Bool, actionTitle: String, serverName: String) {
        guard Self.shouldPost(isBackgrounded: isBackgrounded, authorizationGranted: authorizationGranted) else { return }
        let composed = Self.composeContent(success: success, actionTitle: actionTitle, serverName: serverName)
        let content = UNMutableNotificationContent()
        content.title = composed.title
        content.body = composed.body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        Task { [center] in
            try? await center.add(request)
        }
    }

    private func requestAuthorizationIfNeeded() {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        Task { [weak self, center] in
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            self?.authorizationGranted = granted
        }
    }

    // MARK: - Pure logic (unit-tested without touching UNUserNotificationCenter)
    //
    // All three below are `nonisolated`: they touch no instance state, so
    // XCTest can call them directly from a plain (non-`@MainActor`) test
    // method without an `await`/actor hop — that's the whole point of
    // factoring them out of the actor-isolated I/O above.

    /// Foreground-suppression + permission-gate decision: post a
    /// notification only when the app is backgrounded (foreground already
    /// has the in-app toast/haptic) AND authorization was granted — denied
    /// or not-yet-determined both skip silently rather than blocking
    /// anything.
    nonisolated static func shouldPost(isBackgrounded: Bool, authorizationGranted: Bool) -> Bool {
        isBackgrounded && authorizationGranted
    }

    /// `true` for any status that lets a local notification actually be
    /// delivered — `.authorized` plus the lighter-weight `.provisional`
    /// (quiet delivery straight to Notification Center) and `.ephemeral`
    /// (App Clips) grants.
    nonisolated static func isGranted(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: true
        case .denied, .notDetermined: false
        @unknown default: false
        }
    }

    /// Composes the notification title/body. Generic across every tracked
    /// action kind (power actions, management actions, rescale, row quick
    /// actions) rather than hard-coded per-action copy, since one service
    /// backs reboot/rebuild/rescale/snapshot/etc — `actionTitle` is the
    /// human title already used elsewhere for that action (`PowerAction
    /// .title`, `ServerManagementAction.title`, "Resize", ...). Never
    /// includes anything beyond the action title and server name — no
    /// tokens, passwords, or other credential-bearing content.
    nonisolated static func composeContent(success: Bool, actionTitle: String, serverName: String) -> (title: String, body: String) {
        if success {
            return ("\(actionTitle) Complete", "\(serverName) is ready.")
        }
        return ("\(actionTitle) Failed", "\(serverName) needs attention — check the app for details.")
    }
}
