import CryptoKit
import Foundation

/// Generates Ed25519 SSH key pairs entirely on-device (CryptoKit; nothing
/// ever leaves the phone unencrypted) and encodes them in the wire formats
/// `ssh-keygen` produces, so the public key can be pasted straight into
/// Hetzner's "Add SSH key" flow and the private key can be imported by any
/// standard OpenSSH-compatible client.
///
/// - Important: Key material must never be logged (`print`, `os_log`, etc).
///   The only sanctioned ways to get key material off this type are
///   `savePrivateKey` (Keychain, this device only) and, for user-initiated
///   export, `SensitivePasteboard` — never write it to `UserDefaults`, files,
///   or SwiftData.
enum SSHKeyGenerator {
    private static let service = "com.hetzly.ssh-private-key"
    private static let store = KeychainStore()

    /// Generates a new Ed25519 key pair with `comment` embedded in the
    /// public key line (conventionally `user@host` or a free-form label).
    static func generateEd25519(comment: String) -> GeneratedSSHKey {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKeyRaw = privateKey.publicKey.rawRepresentation
        let privateKeySeed = privateKey.rawRepresentation

        let publicKeyBlob = sshEd25519PublicKeyBlob(publicKeyRaw: publicKeyRaw)

        let publicKeyOpenSSH = "ssh-ed25519 \(publicKeyBlob.base64EncodedString()) \(comment)"
        let privateKeyOpenSSH = openSSHPrivateKeyPEM(
            publicKeyRaw: publicKeyRaw,
            privateKeySeed: privateKeySeed,
            comment: comment
        )
        let fingerprintSHA256 = "SHA256:" + base64URLSafeNoPadding(SHA256.hash(data: publicKeyBlob))

        return GeneratedSSHKey(
            publicKeyOpenSSH: publicKeyOpenSSH,
            privateKeyOpenSSH: privateKeyOpenSSH,
            fingerprintSHA256: fingerprintSHA256
        )
    }

    // MARK: - Keychain storage

    /// Stores `key`'s private key material under `name` (service
    /// `"com.hetzly.ssh-private-key"`, account = `name`).
    static func savePrivateKey(_ key: GeneratedSSHKey, name: String) throws {
        try store.saveString(key.privateKeyOpenSSH, service: service, account: name)
    }

    /// Loads the OpenSSH-formatted private key previously saved under `name`,
    /// or `nil` if none exists.
    static func loadPrivateKey(name: String) throws -> String? {
        try store.readString(service: service, account: name)
    }

    /// Deletes the private key stored under `name`. Idempotent — deleting a
    /// name that was never saved is not an error.
    static func deletePrivateKey(name: String) throws {
        try store.delete(service: service, account: name)
    }

    // MARK: - SSH wire encoding

    /// The standard SSH wire-format public key blob: `string "ssh-ed25519"`
    /// followed by `string <raw 32-byte public key>`. This is what gets
    /// base64-encoded for the `ssh-ed25519 AAAA...` public key line, and
    /// what SHA-256 fingerprints are computed over.
    private static func sshEd25519PublicKeyBlob(publicKeyRaw: Data) -> Data {
        var encoder = SSHWireEncoder()
        encoder.append(string: "ssh-ed25519")
        encoder.append(data: publicKeyRaw)
        return encoder.data
    }

    /// Builds the full `openssh-key-v1` private key structure and wraps it
    /// in PEM armor, matching the exact format `ssh-keygen -t ed25519`
    /// produces for an unencrypted (`ciphername "none"`) key.
    private static func openSSHPrivateKeyPEM(
        publicKeyRaw: Data,
        privateKeySeed: Data,
        comment: String
    ) -> String {
        let publicKeyBlob = sshEd25519PublicKeyBlob(publicKeyRaw: publicKeyRaw)

        // OpenSSH's ed25519 "private key" field is the 64-byte libsodium
        // secret key: the 32-byte seed followed by the 32-byte public key.
        var secretKeyField = Data()
        secretKeyField.append(privateKeySeed)
        secretKeyField.append(publicKeyRaw)

        // A random 32-bit "checkint" repeated twice lets a reader verify
        // decryption succeeded; for an unencrypted key it's just a nonce.
        var randomNumberGenerator = SystemRandomNumberGenerator()
        let checkint = UInt32.random(in: UInt32.min...UInt32.max, using: &randomNumberGenerator)

        var privateSection = SSHWireEncoder()
        privateSection.append(uint32: checkint)
        privateSection.append(uint32: checkint)
        privateSection.append(string: "ssh-ed25519")
        privateSection.append(data: publicKeyRaw)
        privateSection.append(data: secretKeyField)
        privateSection.append(string: comment)

        // Pad with 0x01, 0x02, 0x03... until the section is a multiple of
        // the (unencrypted, so block size 8) cipher block size.
        var padded = privateSection.data
        var paddingByte: UInt8 = 1
        while padded.count % 8 != 0 {
            padded.append(paddingByte)
            paddingByte += 1
        }

        var body = SSHWireEncoder()
        body.append(string: "none") // ciphername
        body.append(string: "none") // kdfname
        body.append(string: "") // kdfoptions (empty)
        body.append(uint32: 1) // number of keys
        body.append(data: publicKeyBlob)
        body.append(data: padded)

        var fullBytes = Data("openssh-key-v1".utf8)
        fullBytes.append(0) // NUL terminator on the magic string
        fullBytes.append(body.data)

        let base64 = fullBytes.base64EncodedString()
        let wrapped = wrapBase64(base64, lineLength: 70)

        return "-----BEGIN OPENSSH PRIVATE KEY-----\n\(wrapped)\n-----END OPENSSH PRIVATE KEY-----\n"
    }

    private static func wrapBase64(_ base64: String, lineLength: Int) -> String {
        var lines: [String] = []
        var remaining = Substring(base64)
        while !remaining.isEmpty {
            let end = remaining.index(remaining.startIndex, offsetBy: lineLength, limitedBy: remaining.endIndex) ?? remaining.endIndex
            lines.append(String(remaining[remaining.startIndex..<end]))
            remaining = remaining[end...]
        }
        return lines.joined(separator: "\n")
    }

    private static func base64URLSafeNoPadding(_ digest: SHA256Digest) -> String {
        Data(digest).base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}

/// Result of generating an SSH key pair. Public key material is safe to
/// display, copy, and submit to Hetzner's API; private key material must
/// only be persisted via `SSHKeyGenerator.savePrivateKey` (Keychain) and, for
/// user-initiated export, copied via `SensitivePasteboard` — never logged,
/// never written elsewhere.
struct GeneratedSSHKey: Sendable, Equatable {
    /// `"ssh-ed25519 <base64> <comment>"`, ready to submit as-is.
    let publicKeyOpenSSH: String
    /// PEM-armored `openssh-key-v1` private key, ready to import into any
    /// OpenSSH-compatible client (`ssh-keygen -y -f`, `ssh -i`, ...).
    let privateKeyOpenSSH: String
    /// `"SHA256:<base64-no-padding>"`, matching `ssh-keygen -l -f`'s output.
    let fingerprintSHA256: String
}

/// Minimal big-endian SSH wire-format encoder (RFC 4251 §5): `uint32` is a
/// 4-byte big-endian integer, `string` is a `uint32` length prefix followed
/// by raw bytes.
private struct SSHWireEncoder {
    private(set) var data = Data()

    mutating func append(uint32 value: UInt32) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    mutating func append(string: String) {
        append(data: Data(string.utf8))
    }

    mutating func append(data raw: Data) {
        append(uint32: UInt32(clamping: raw.count))
        data.append(raw)
    }
}
