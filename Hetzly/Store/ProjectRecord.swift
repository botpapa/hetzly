import Foundation
import SwiftData

/// A saved Hetzner Cloud project (a name the user gave a token). The token
/// itself is never stored here — see `TokenVault` — only this metadata
/// lives in SwiftData.
@Model
final class ProjectRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var sortOrder: Int

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), sortOrder: Int) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }
}
