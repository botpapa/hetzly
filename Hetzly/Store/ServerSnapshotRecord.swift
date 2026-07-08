import Foundation
import SwiftData

/// A cached, JSON-encoded `[Server]` payload for a project, so the Dashboard
/// has something to show before the network round-trip completes. Contains
/// only server metadata returned by the Hetzner API — no secrets, so it's
/// safe to persist outside the keychain.
@Model
final class ServerSnapshotRecord {
    var projectID: UUID
    var payload: Data
    var updatedAt: Date

    init(projectID: UUID, payload: Data, updatedAt: Date = Date()) {
        self.projectID = projectID
        self.payload = payload
        self.updatedAt = updatedAt
    }
}
