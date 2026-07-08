import Foundation

/// Durable, on-device store for server root passwords the API hands back at
/// creation/reset/rescue time.
///
/// `CreateServerViewModel` (and, in a future wave, the reset-root-password
/// and enable-rescue-mode flows) used to hold a returned root password only
/// in memory while its result screen was on screen — if the app was killed
/// right then (background jetsam, crash, force-quit), the password was gone
/// forever and the server would need a rescue-mode reset just to log in.
/// This vault closes that gap: the moment a root password arrives from the
/// API, it's written here, and it stays there **permanently** until the user
/// explicitly deletes it — this is intentionally not a "clear on
/// acknowledge" cache. Passwords are precious, one-shot secrets Hetzner
/// itself never shows again; losing them because a result screen was
/// dismissed is exactly the failure mode this exists to prevent.
///
/// Storage shape:
/// - Secret material lives in the Keychain under service
///   `rootPasswordService`, one item per `account(forServerID:)`
///   (`"server-<id>"`), saved with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
///   (via `KeychainStore`) — **ThisDeviceOnly**: never synced via iCloud
///   Keychain, never leaves this device, and never written to logs,
///   `UserDefaults`, or SwiftData.
/// - A small **registry of server IDs only** — never secret material — lives
///   in `UserDefaults` under `knownIDsDefaultsKey`, so callers can cheaply
///   ask "which servers have a saved password?" (e.g. to show a banner)
///   without a Keychain round trip for every server.
/// - Deletion is entirely user-initiated: `deleteRootPassword(serverID:)` is
///   only ever called from an explicit "Delete" action in the UI, never
///   automatically on a "Done"/acknowledge tap.
///
/// Current callers (this wave): `CreateServerViewModel.createServer` saves
/// on receipt; `CreateServerFlow` reads `knownServerIDs()` to show a "your
/// last server's password is saved on this device" banner and lets the user
/// view (never auto-deletes) or explicitly delete it from a sheet.
/// `ServerDetailViewModel`'s reset-password/rescue-password save points and
/// a "Credentials" section on the server detail screen are planned for a
/// following wave (a different worker owns those surfaces) — the flat
/// `(serverID) -> password` shape here is deliberately generic so wiring
/// those in later is a one-line `saveRootPassword` call, no API changes.
enum ServerCredentialsVault {
    /// Keychain service for saved server root passwords.
    static let rootPasswordService = "com.hetzly.server-credentials"

    private static let knownIDsDefaultsKey = "com.hetzly.server-credentials-ids"
    private static let store = KeychainStore()

    private static func account(forServerID serverID: Int) -> String {
        "server-\(serverID)"
    }

    /// Saves (or overwrites) the root password for `serverID`. A newer
    /// password — e.g. from a subsequent rescue/reset — replaces whatever
    /// was stored before, and records the id in the registry.
    static func saveRootPassword(_ password: String, serverID: Int) throws {
        try store.saveString(password, service: rootPasswordService, account: account(forServerID: serverID))
        var ids = knownServerIDs()
        if !ids.contains(serverID) {
            ids.append(serverID)
            UserDefaults.standard.set(ids, forKey: knownIDsDefaultsKey)
        }
    }

    /// Reads the saved root password for `serverID`, or `nil` if none is
    /// stored (or the Keychain read failed).
    static func rootPassword(serverID: Int) -> String? {
        (try? store.readString(service: rootPasswordService, account: account(forServerID: serverID))) ?? nil
    }

    /// Deletes the saved root password for `serverID` (idempotent) and
    /// removes it from the registry. Only ever call this from an explicit,
    /// user-initiated "Delete" action — this vault never auto-deletes on a
    /// "Done"/acknowledge tap.
    static func deleteRootPassword(serverID: Int) {
        try? store.delete(service: rootPasswordService, account: account(forServerID: serverID))
        var ids = knownServerIDs()
        ids.removeAll { $0 == serverID }
        UserDefaults.standard.set(ids, forKey: knownIDsDefaultsKey)
    }

    /// Server IDs with a root password currently saved — ids only, never the
    /// secret itself. Cheap to read on every launch/flow entry (UserDefaults,
    /// no Keychain access).
    static func knownServerIDs() -> [Int] {
        UserDefaults.standard.array(forKey: knownIDsDefaultsKey) as? [Int] ?? []
    }
}
