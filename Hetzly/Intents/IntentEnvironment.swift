import Foundation
import HetznerKit
import SwiftData

/// Lightweight, `AppIntents`-only counterpart to `AppContainer`'s SwiftData
/// bootstrap (`Hetzly/App/AppContainer.swift`). Intents run in-process (no
/// extension target) but are not guaranteed to run after `HetzlyApp`/
/// `AppContainer` has been constructed — Shortcuts and Siri can invoke a
/// registered intent cold, before the app's own scene ever launches — so
/// this builds its own `ModelContainer` via the same `hetzlyModelContainer()`
/// the Store module owns (`Hetzly/Store/HetzlyModelContainer.swift`), with
/// the same in-memory fallback `AppContainer.makeDefault()` uses. Unlike
/// `AppContainer`, failure to build even the in-memory fallback is
/// propagated as `nil`/thrown rather than `try!` — an intent can always
/// finish by throwing a dialog-worthy error instead of crashing the host
/// process (which, for an in-process intent, would also kill the app if it
/// happens to be foregrounded).
///
/// One container is cached for the process lifetime so repeated intent
/// invocations in the same launch don't reopen the on-disk store.
@MainActor
enum IntentEnvironment {
    private static var cachedContainer: ModelContainer?

    /// The shared `ModelContext`, or `nil` if even the in-memory fallback
    /// store couldn't be built (a structural schema defect, not a runtime
    /// condition — see `AppContainer.buildModelContainer()`'s equivalent
    /// comment).
    static func modelContext() -> ModelContext? {
        if let cachedContainer {
            return cachedContainer.mainContext
        }
        guard let container = try? buildModelContainer() else { return nil }
        cachedContainer = container
        return container.mainContext
    }

    static func projectsStore() -> ProjectsStore? {
        modelContext().map(ProjectsStore.init(context:))
    }

    static func snapshotStore() -> SnapshotStore? {
        modelContext().map(SnapshotStore.init(context:))
    }

    /// Builds a `CloudClient` for `projectID` straight from `TokenVault`,
    /// bypassing `AppContainer.cloudClient(for:)`'s cache — intents are
    /// short-lived, one-shot invocations, so there's no benefit to caching a
    /// client (or its internal rate limiter) across calls the way the app's
    /// own `AppContainer` does across a whole session.
    static func cloudClient(forProjectID projectID: UUID) throws -> CloudClient {
        let projectName = projectsStore()?.projects.first(where: { $0.id == projectID })?.name ?? "This project"
        guard let token = (try? TokenVault.cloudToken(projectID: projectID.uuidString)) ?? nil else {
            throw HetzlyIntentError.needsToken(projectName: projectName)
        }
        return CloudClient(token: token)
    }

    private static func buildModelContainer() throws -> ModelContainer {
        if let container = try? hetzlyModelContainer() {
            return container
        }
        let fallbackConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: ProjectRecord.self, ServerSnapshotRecord.self, RobotAccountRecord.self,
            configurations: fallbackConfiguration
        )
    }
}
