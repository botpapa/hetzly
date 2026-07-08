import Foundation
import SwiftData

/// Builds the app's single SwiftData container backing `ProjectRecord`,
/// `ServerSnapshotRecord`, and `RobotAccountRecord`. On-disk and persistent,
/// no CloudKit — snapshots are non-secret cache data, and cloud
/// tokens/Robot passwords never live here (see `TokenVault`, which is the
/// only sanctioned place for credential storage).
func hetzlyModelContainer() throws -> ModelContainer {
    let schema = Schema([ProjectRecord.self, ServerSnapshotRecord.self, RobotAccountRecord.self])
    let configuration = ModelConfiguration(schema: schema)
    return try ModelContainer(for: schema, configurations: [configuration])
}
