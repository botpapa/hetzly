import AppIntents
import HetznerKit

/// A Hetzner Cloud server exposed to Shortcuts/Siri as a pickable entity.
/// `id` is `"<projectUUID>#<serverID>"` since a bare `Server.id` (an `Int`)
/// is only unique within one project — Hetzly has no global server ID.
///
/// Resolved entirely from on-device `SnapshotStore` data (the cached
/// `[Server]` JSON per project, same store Dashboard reads) rather than a
/// live API call: `EntityQuery.entities(for:)`/`suggestedEntities()` back
/// the Shortcuts parameter picker and Siri's "which server?" disambiguation,
/// both of which need to resolve fast and offline. Intents that actually
/// *act* on a server (`ServerStatusIntent`, `RebootServerIntent`) go live
/// via `CloudClient` themselves once an entity is picked.
struct ServerEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Hetzner Server")
    }

    static let defaultQuery = ServerEntityQuery()

    let projectID: UUID
    let serverID: Int
    let name: String
    let status: ServerStatus
    let ipv4: String?

    var id: String { Self.makeID(projectID: projectID, serverID: serverID) }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(status.displayName)",
            image: .init(systemName: "server.rack")
        )
    }

    static func makeID(projectID: UUID, serverID: Int) -> String {
        "\(projectID.uuidString)#\(serverID)"
    }

    /// Splits a composite id back into its parts. `nil` for anything
    /// malformed (a stale id from a since-deleted project, or garbage from
    /// outside Hetzly) so callers can degrade gracefully instead of
    /// crashing on a force-unwrap.
    static func parse(id: String) -> (projectID: UUID, serverID: Int)? {
        let parts = id.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let projectID = UUID(uuidString: String(parts[0])),
              let serverID = Int(parts[1])
        else {
            return nil
        }
        return (projectID, serverID)
    }
}

/// Resolves `ServerEntity` values from every project's `SnapshotStore`
/// cache. Read-only and offline: it never talks to `CloudClient`, so a
/// server that was renamed/deleted since the last Dashboard refresh may be
/// briefly stale here — acceptable for a picker, since the intents that act
/// on the resolved entity re-fetch live state themselves.
struct ServerEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [ServerEntity] {
        let wanted = Set(identifiers)
        return Self.allServerEntities().filter { wanted.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [ServerEntity] {
        Self.allServerEntities()
    }

    /// Builds every `ServerEntity` across every configured project. Guards
    /// against the common empty-state cases (no projects saved yet, or a
    /// project with no snapshot yet because Dashboard hasn't loaded once) by
    /// simply skipping them rather than throwing — an empty picker is a
    /// normal, expected state for a fresh install.
    @MainActor
    private static func allServerEntities() -> [ServerEntity] {
        guard let projectsStore = IntentEnvironment.projectsStore(), !projectsStore.projects.isEmpty else {
            return []
        }
        guard let snapshotStore = IntentEnvironment.snapshotStore() else {
            return []
        }

        var result: [ServerEntity] = []
        for project in projectsStore.projects {
            guard let snapshot = snapshotStore.loadServers(projectID: project.id) else { continue }
            for server in snapshot.servers {
                result.append(
                    ServerEntity(
                        projectID: project.id,
                        serverID: server.id,
                        name: server.name,
                        status: server.status,
                        ipv4: server.publicNet.ipv4?.ip
                    )
                )
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
