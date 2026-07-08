import Foundation
import HetznerKit
import SwiftData

/// Caches the last-known `[Server]` list per project as JSON, so the
/// Dashboard has something to render before (or if) the network call
/// completes. One record per `projectID` — writes upsert, corrupt reads
/// self-heal by deleting the bad record.
@MainActor
final class SnapshotStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func saveServers(_ servers: [Server], projectID: UUID) {
        guard let payload = try? JSONEncoder().encode(servers) else { return }
        let now = Date()

        if let existing = fetchRecord(projectID: projectID) {
            existing.payload = payload
            existing.updatedAt = now
        } else {
            context.insert(ServerSnapshotRecord(projectID: projectID, payload: payload, updatedAt: now))
        }
        try? context.save()
    }

    func loadServers(projectID: UUID) -> (servers: [Server], updatedAt: Date)? {
        guard let record = fetchRecord(projectID: projectID) else { return nil }

        guard let servers = try? JSONDecoder().decode([Server].self, from: record.payload) else {
            // Self-heal: drop the corrupt payload so future loads don't keep
            // failing on the same bad bytes.
            context.delete(record)
            try? context.save()
            return nil
        }

        return (servers, record.updatedAt)
    }

    private func fetchRecord(projectID: UUID) -> ServerSnapshotRecord? {
        let predicate = #Predicate<ServerSnapshotRecord> { $0.projectID == projectID }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
