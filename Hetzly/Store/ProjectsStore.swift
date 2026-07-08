import Foundation
import Observation
import SwiftData

/// Owns the list of saved projects. Every mutation writes through
/// `ModelContext` and (for tokens) `TokenVault`, then refetches so
/// `projects` always reflects what's actually persisted.
@MainActor
@Observable
final class ProjectsStore {
    private let context: ModelContext
    private(set) var projects: [ProjectRecord] = []

    init(context: ModelContext) {
        self.context = context
        refresh()
    }

    /// Inserts a new project record and saves its token to the keychain.
    /// If either half fails, both are rolled back so we never end up with a
    /// project that has no retrievable token, or an orphaned keychain entry.
    @discardableResult
    func addProject(name: String, token: String) throws -> ProjectRecord {
        let nextSortOrder = (projects.map(\.sortOrder).max() ?? -1) + 1
        let record = ProjectRecord(name: name, sortOrder: nextSortOrder)

        try TokenVault.saveCloudToken(token, projectID: record.id.uuidString)

        context.insert(record)
        do {
            try context.save()
        } catch {
            context.delete(record)
            try? TokenVault.deleteCloudToken(projectID: record.id.uuidString)
            refresh()
            throw error
        }

        refresh()
        return record
    }

    func rename(_ project: ProjectRecord, to newName: String) {
        project.name = newName
        try? context.save()
        refresh()
    }

    /// Deletes the project record, its keychain token, and any cached
    /// server snapshots for it.
    func remove(_ project: ProjectRecord) throws {
        let projectID = project.id

        let predicate = #Predicate<ServerSnapshotRecord> { $0.projectID == projectID }
        let snapshots = try context.fetch(FetchDescriptor(predicate: predicate))
        for snapshot in snapshots {
            context.delete(snapshot)
        }

        context.delete(project)
        try context.save()

        try TokenVault.deleteCloudToken(projectID: projectID.uuidString)

        refresh()
    }

    func token(for project: ProjectRecord) throws -> String? {
        try TokenVault.cloudToken(projectID: project.id.uuidString)
    }

    /// Replaces the Keychain-stored API token for `project` in place — the
    /// record itself (id, name, sortOrder) is never touched. Callers must
    /// also invalidate any cached `CloudClient` for this project (see
    /// `AppContainer.invalidateCloudClient(for:)`) so the next access
    /// rebuilds with the fresh token; this method has no knowledge of that
    /// cache.
    func updateToken(for project: ProjectRecord, to newToken: String) throws {
        try TokenVault.saveCloudToken(newToken, projectID: project.id.uuidString)
    }

    /// Reorders `projects` per a SwiftUI `List.onMove` gesture, then
    /// rewrites every record's `sortOrder` sequentially (0...n) to match the
    /// new array order and persists it.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var reordered = projects
        reordered.move(fromOffsets: source, toOffset: destination)

        for (index, project) in reordered.enumerated() {
            project.sortOrder = index
        }
        try? context.save()

        refresh()
    }

    private func refresh() {
        let descriptor = FetchDescriptor<ProjectRecord>(
            sortBy: [
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.name),
            ]
        )
        projects = (try? context.fetch(descriptor)) ?? []
    }
}
