import UIKit
import UniformTypeIdentifiers

/// Copies short-lived secrets (rescue passwords, freshly generated keys) to
/// the system pasteboard with an expiration so they don't linger. Nothing
/// copied through here is ever logged.
enum SensitivePasteboard {
    /// Copies `string` to the general pasteboard, restricted to this device
    /// (`.localOnly`) and automatically expiring after `expiresIn` seconds
    /// (default 60s).
    static func copy(_ string: String, expiresIn: TimeInterval = 60) {
        let expirationDate = Date(timeIntervalSinceNow: expiresIn)
        let item: [String: Any] = [UTType.utf8PlainText.identifier: string]
        UIPasteboard.general.setItems(
            [item],
            options: [
                .expirationDate: expirationDate,
                .localOnly: true
            ]
        )
    }
}
