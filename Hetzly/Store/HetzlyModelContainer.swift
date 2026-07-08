import Foundation
import SwiftData

/// Builds the app's single SwiftData container backing `ProjectRecord`,
/// `ServerSnapshotRecord`, `RobotAccountRecord`, and
/// `StorageBoxAccountRecord`. On-disk and persistent, no CloudKit —
/// snapshots are non-secret cache data, and cloud tokens/Robot
/// passwords/Storage Box tokens never live here (see `TokenVault` and
/// `StorageBoxAccountsStore`'s private `StorageBoxTokenVault`, the only
/// sanctioned places for credential storage).
func hetzlyModelContainer() throws -> ModelContainer {
    let schema = Schema([
        ProjectRecord.self, ServerSnapshotRecord.self, RobotAccountRecord.self, StorageBoxAccountRecord.self,
    ])
    let configuration = ModelConfiguration(schema: schema)
    return try ModelContainer(for: schema, configurations: [configuration])
}
