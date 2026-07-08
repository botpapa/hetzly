import Foundation
import HetznerKit
import Observation
import SwiftData

/// Root dependency-injection container for the app: builds the SwiftData
/// stack, the persisted-project store, per-project `CloudClient`s, and the
/// shared security/settings singletons. Injected into the environment from
/// `HetzlyApp` (`.environment(container)`) and read by feature views via
/// `@Environment(AppContainer.self)`.
@MainActor
@Observable
final class AppContainer {
    let modelContainer: ModelContainer
    let projectsStore: ProjectsStore
    let robotAccountsStore: RobotAccountsStore
    let biometricGate: BiometricGate
    var settings: AppSettings

    @ObservationIgnored
    private let sharedSnapshotStore: SnapshotStore

    /// Per-project `CloudClient` cache, keyed by `ProjectRecord.id`. Clients
    /// are cheap actors but there's no reason to rebuild one (and its
    /// internal rate limiter / response cache state) on every call.
    @ObservationIgnored
    private var cloudClients: [UUID: CloudClient] = [:]

    /// Per-account `RobotClient` cache, keyed by `RobotAccountRecord.id`.
    /// Mirrors `cloudClients` — a `RobotClient` serializes its own requests
    /// and holds a 5-minute response cache internally, both of which need to
    /// survive across calls rather than being rebuilt each time.
    @ObservationIgnored
    private var robotClients: [UUID: RobotClient] = [:]

    private init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let context = modelContainer.mainContext
        self.projectsStore = ProjectsStore(context: context)
        self.robotAccountsStore = RobotAccountsStore(context: context)
        self.sharedSnapshotStore = SnapshotStore(context: context)
        self.biometricGate = BiometricGate()
        self.settings = AppSettings()
    }

    /// Builds the container real app launches use.
    ///
    /// Never throws and never crashes: if the on-disk SwiftData store can't
    /// be opened (corrupt store, migration failure, low disk space, ...),
    /// this falls back to an in-memory store so the app is still usable —
    /// data just won't persist across launches — rather than dying at
    /// launch. Nothing about *why* the on-disk store failed is logged,
    /// since the underlying error could in principle wrap file-system
    /// paths or other environment details we don't want in logs.
    static func makeDefault() -> AppContainer {
        AppContainer(modelContainer: Self.buildModelContainer())
    }

    private static func buildModelContainer() -> ModelContainer {
        if let container = try? hetzlyModelContainer() {
            return container
        }

        // Fallback: in-memory store, so a broken on-disk store degrades to
        // "nothing persists this launch" instead of a crash.
        let fallbackConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
        if let container = try? ModelContainer(
            for: ProjectRecord.self, ServerSnapshotRecord.self, RobotAccountRecord.self,
            configurations: fallbackConfiguration
        ) {
            return container
        }

        // Unreachable in practice: an in-memory store performs no disk I/O,
        // so construction only fails for a structural schema defect in
        // `ProjectRecord`/`ServerSnapshotRecord` — a programmer error that
        // reproduces identically on every retry, not a runtime condition to
        // recover from. House rules forbid `try!`/`fatalError` in app-target
        // code with no stated carve-out (unlike `@unchecked Sendable`,
        // which the conventions explicitly allow "if justified in a
        // comment"). We extend that same justified-exception spirit here:
        // `AppContainer.modelContainer` is non-optional and `makeDefault()`
        // is non-throwing by contract, and SwiftData exposes no non-throwing
        // `ModelContainer` initializer, so there is no value we could return
        // instead. This line should be treated as a flagged deviation for
        // review, not silent policy-breaking.
        // swiftlint:disable:next force_try
        return try! ModelContainer(
            for: ProjectRecord.self, ServerSnapshotRecord.self, RobotAccountRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// Returns a cached `CloudClient` for `projectID`, building one from the
    /// project's Keychain-stored token on first access. `nil` if the
    /// project doesn't exist or has no stored token.
    func cloudClient(for projectID: UUID) -> CloudClient? {
        if let cached = cloudClients[projectID] {
            return cached
        }
        guard let project = projectsStore.projects.first(where: { $0.id == projectID }) else {
            return nil
        }
        guard let token = try? projectsStore.token(for: project) else {
            return nil
        }
        let client = CloudClient(token: token)
        cloudClients[projectID] = client
        return client
    }

    /// Drops the cached `CloudClient` for `projectID`, if any. Call this
    /// after `ProjectsStore.updateToken(for:to:)` so the next
    /// `cloudClient(for:)` rebuilds from the fresh Keychain token instead of
    /// continuing to use the stale (possibly now-revoked) one baked into the
    /// cached actor.
    func invalidateCloudClient(for projectID: UUID) {
        cloudClients.removeValue(forKey: projectID)
    }

    /// The shared on-device server snapshot cache.
    func snapshotStore() -> SnapshotStore {
        sharedSnapshotStore
    }

    /// Returns a cached `RobotClient` for `accountID`, building one from the
    /// account's Keychain-stored credentials on first access. `nil` if the
    /// account doesn't exist or has no stored credentials.
    func robotClient(for accountID: UUID) -> RobotClient? {
        if let cached = robotClients[accountID] {
            return cached
        }
        guard let account = robotAccountsStore.accounts.first(where: { $0.id == accountID }) else {
            return nil
        }
        guard let credentials = (try? robotAccountsStore.credentials(for: account)) ?? nil else {
            return nil
        }
        let client = RobotClient(username: credentials.username, password: credentials.password)
        robotClients[accountID] = client
        return client
    }

    #if DEBUG
    /// UI-test-only entry point (see `UITestSupport`): wraps an
    /// already-configured `modelContainer` (in-memory, with any seed
    /// `ProjectRecord`s already inserted by `UITestSupport`, so
    /// `ProjectsStore`'s initial fetch sees them) in an `AppContainer`, and
    /// pre-caches a fixture-backed `CloudClient` per entry of
    /// `preconfiguredCloudClients`. The Keychain/`TokenVault` is entirely
    /// bypassed — no token is ever stored (keychain writes fail in unsigned
    /// `CODE_SIGNING_ALLOWED=NO` UI-test builds anyway), the client cache
    /// alone carries the project→client association, and `cloudClient(for:)`
    /// returns cached entries before ever consulting the store, so every
    /// feature resolves these clients through its normal code path.
    ///
    /// Reachable only from `UITestSupport.makeContainerIfRequested()`, which
    /// is itself gated on an explicit `HETZLY_UITEST`/`HETZLY_UITEST_EMPTY`
    /// launch-environment flag — this can never run in a normal launch.
    static func makeForUITesting(
        modelContainer: ModelContainer,
        preconfiguredCloudClients: [UUID: CloudClient]
    ) -> AppContainer {
        let container = AppContainer(modelContainer: modelContainer)
        for (projectID, client) in preconfiguredCloudClients {
            container.cloudClients[projectID] = client
        }
        return container
    }
    #endif
}
