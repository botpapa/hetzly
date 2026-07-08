import Foundation
import SwiftData

/// Builds the app's single SwiftData container backing `ProjectRecord` and
/// `ServerSnapshotRecord`. On-disk and persistent, no CloudKit — snapshots
/// are non-secret cache data, and cloud tokens never live here (see
/// `TokenVault`, which is the only sanctioned place for credential storage).
func hetzlyModelContainer() throws -> ModelContainer {
    let schema = Schema([ProjectRecord.self, ServerSnapshotRecord.self])
    let configuration = ModelConfiguration(schema: schema)
    return try ModelContainer(for: schema, configurations: [configuration])
}
