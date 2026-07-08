import Foundation
import SwiftData

/// A saved Hetzner Storage Box API account (a label the user gave an API
/// token pair for Hetzner's new unified `api.hetzner.com/v1` Storage Box
/// endpoints — separate from both a Cloud project token and a Robot
/// webservice login). The token itself is never stored here — see
/// `StorageBoxTokenVault` in `StorageBoxAccountsStore.swift` — only this
/// metadata lives in SwiftData.
@Model
final class StorageBoxAccountRecord {
    @Attribute(.unique) var id: UUID
    var label: String
    var createdAt: Date

    init(id: UUID = UUID(), label: String, createdAt: Date = Date()) {
        self.id = id
        self.label = label
        self.createdAt = createdAt
    }
}
