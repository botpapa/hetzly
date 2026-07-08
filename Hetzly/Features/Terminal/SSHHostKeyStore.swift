import Crypto
import Foundation
import NIOSSH

/// Trust-on-first-use (TOFU) host key store for `SSHConnection`.
///
/// The **first** time this app connects to a given `host:port`, whatever
/// SHA-256 fingerprint the server presents is remembered. Every later
/// connection compares the freshly-presented fingerprint against the
/// remembered one; a mismatch means either the host key rotated (e.g. the
/// server was reinstalled) or something is intercepting the connection, and
/// is surfaced to the UI as `SSHConnection.State.hostKeyMismatch` rather than
/// silently accepted.
///
/// - Important: Only the fingerprint **string** (`"SHA256:base64…"`, the
///   same format `ssh-keygen -l` prints) is persisted, in `UserDefaults`.
///   Never the host's actual public key bytes, and never anything about this
///   device's own keys — this store has nothing to do with
///   `SSHKeyGenerator`/`ServerCredentialsVault`'s Keychain-held secrets.
enum SSHHostKeyStore {
    private static let defaultsKeyPrefix = "com.hetzly.ssh-host-key-fingerprint."

    private static func defaultsKey(host: String, port: Int) -> String {
        "\(defaultsKeyPrefix)\(host):\(port)"
    }

    /// The fingerprint trusted for `host:port`, or `nil` if this is the
    /// first time this app has seen that host.
    static func trustedFingerprint(host: String, port: Int) -> String? {
        UserDefaults.standard.string(forKey: defaultsKey(host: host, port: port))
    }

    /// Records `fingerprint` as trusted for `host:port`. Called on first
    /// connection (TOFU) — never silently called again to overwrite a
    /// mismatched fingerprint; that requires an explicit user action
    /// (`updateTrustedFingerprint`) surfaced from the host-key-mismatch UI
    /// state.
    static func trust(fingerprint: String, host: String, port: Int) {
        UserDefaults.standard.set(fingerprint, forKey: defaultsKey(host: host, port: port))
    }

    /// Explicitly replaces the trusted fingerprint for `host:port`, e.g.
    /// after the user reviews a host-key-mismatch warning and chooses to
    /// trust the new key anyway (a reinstalled server is the common benign
    /// case). Same storage path as `trust` — kept as a separate name only so
    /// call sites read as intentional overwrites, not first-use trust.
    static func updateTrustedFingerprint(_ fingerprint: String, host: String, port: Int) {
        trust(fingerprint: fingerprint, host: host, port: port)
    }

    /// Removes any remembered fingerprint for `host:port`, so the next
    /// connection is treated as first-use again.
    static func forget(host: String, port: Int) {
        UserDefaults.standard.removeObject(forKey: defaultsKey(host: host, port: port))
    }

    /// The `"SHA256:base64…"` fingerprint for `hostKey`, computed the same
    /// way `ssh-keygen -l` and `SSHKeyGenerator.generateEd25519` do: SHA-256
    /// over the raw SSH wire-format key blob (algorithm identifier + key
    /// bytes), base64, no padding.
    ///
    /// swift-nio-ssh doesn't expose the wire-format blob directly, but it
    /// does expose `String(openSSHPublicKey:)`, which is
    /// `"<algorithm> <base64(wire-format blob)> "`  — the base64 component
    /// there IS the wire-format blob, so decoding it back out gives us
    /// exactly what `ssh-keygen -l`'s fingerprint is computed over.
    static func fingerprint(of hostKey: NIOSSHPublicKey) -> String {
        let openSSHLine = String(openSSHPublicKey: hostKey)
        let base64Component = openSSHLine
            .split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            .dropFirst()
            .first
            .map(String.init) ?? ""
        let wireBlob = Data(base64Encoded: base64Component) ?? Data()
        let digest = SHA256.hash(data: wireBlob)
        let base64NoPadding = Data(digest).base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))
        return "SHA256:\(base64NoPadding)"
    }
}
