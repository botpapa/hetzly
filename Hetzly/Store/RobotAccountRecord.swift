import Foundation
import SwiftData

/// A saved Hetzner Robot webservice account (a label the user gave a
/// username/password pair for the Robot API — separate from a Hetzner Cloud
/// project token). The password itself is never stored here — see
/// `TokenVault.saveRobotCredentials` — only this metadata lives in SwiftData.
/// The username is duplicated here (also inside the Keychain-stored
/// credentials) purely so the account list can render a subtitle without a
/// Keychain round trip.
@Model
final class RobotAccountRecord {
    @Attribute(.unique) var id: UUID
    var label: String
    var username: String
    var createdAt: Date

    init(id: UUID = UUID(), label: String, username: String, createdAt: Date = Date()) {
        self.id = id
        self.label = label
        self.username = username
        self.createdAt = createdAt
    }
}
