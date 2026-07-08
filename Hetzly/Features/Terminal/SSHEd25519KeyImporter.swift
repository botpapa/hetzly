import Crypto
import CryptoKit
import Foundation
import NIOSSH

/// Converts the OpenSSH-PEM Ed25519 private keys `SSHKeyGenerator` produces
/// (and stores in the Keychain) into a `NIOSSHPrivateKey` swift-nio-ssh can
/// sign auth challenges with.
///
/// - Important: This parser is deliberately narrow. It understands exactly
///   the `openssh-key-v1` layout `SSHKeyGenerator.openSSHPrivateKeyPEM`
///   writes — single Ed25519 key, `ciphername "none"` (unencrypted),
///   `kdfname "none"` — because that is the only shape this app ever
///   generates or stores. It is not a general-purpose OpenSSH key parser
///   (no passphrase/KDF support, no RSA/ECDSA). A key pasted from elsewhere
///   in a different shape throws `SSHEd25519KeyImportError` rather than
///   silently misparsing.
///
/// Round trip: `SSHKeyGenerator.generateEd25519` starts from a CryptoKit
/// `Curve25519.Signing.PrivateKey`, takes its 32-byte `rawRepresentation`
/// seed, and wire-encodes it into the OpenSSH private-key section alongside
/// the 32-byte public key (`seed || publicKey`, the libsodium secret-key
/// convention OpenSSH uses for ed25519). This type reverses exactly that:
/// extract the 32-byte seed back out and hand it to
/// `Curve25519.Signing.PrivateKey(rawRepresentation:)`, then wrap it in
/// `NIOSSHPrivateKey(ed25519Key:)`. No key material is logged at any point.
enum SSHEd25519KeyImporter {
    /// Parses `pem` (as returned by `SSHKeyGenerator.loadPrivateKey`) and
    /// returns a `NIOSSHPrivateKey` ready to hand to
    /// `NIOSSHUserAuthenticationOffer.Offer.privateKey`.
    static func importPrivateKey(fromOpenSSHPEM pem: String) throws -> NIOSSHPrivateKey {
        let seed = try ed25519Seed(fromOpenSSHPEM: pem)
        let cryptoKitKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        return NIOSSHPrivateKey(ed25519Key: cryptoKitKey)
    }

    /// Extracts the raw 32-byte Ed25519 seed from an OpenSSH `openssh-key-v1`
    /// PEM. Exposed separately from `importPrivateKey` so the seed round
    /// trip can be unit-tested without depending on NIOSSH's internals.
    static func ed25519Seed(fromOpenSSHPEM pem: String) throws -> Data {
        let base64 = pem
            .replacingOccurrences(of: "-----BEGIN OPENSSH PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END OPENSSH PRIVATE KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()

        guard !base64.isEmpty, let fullBytes = Data(base64Encoded: base64) else {
            throw SSHEd25519KeyImportError.notPEMArmored
        }

        let magic = Array("openssh-key-v1".utf8) + [0]
        guard fullBytes.count > magic.count, fullBytes.prefix(magic.count).elementsEqual(magic) else {
            throw SSHEd25519KeyImportError.badMagic
        }

        var decoder = SSHWireDecoder(data: fullBytes.suffix(from: fullBytes.startIndex + magic.count))

        let cipherName = try decoder.readString()
        guard cipherName == "none" else {
            throw SSHEd25519KeyImportError.encryptedKeyUnsupported
        }
        let kdfName = try decoder.readString()
        guard kdfName == "none" else {
            throw SSHEd25519KeyImportError.encryptedKeyUnsupported
        }
        _ = try decoder.readData() // kdfoptions, empty for unencrypted keys.
        let keyCount = try decoder.readUInt32()
        guard keyCount == 1 else {
            throw SSHEd25519KeyImportError.unsupportedKeyCount(Int(keyCount))
        }
        _ = try decoder.readData() // public key blob — re-derived from the private section below instead.
        let privateSectionBytes = try decoder.readData()

        var privateDecoder = SSHWireDecoder(data: privateSectionBytes)
        let checkint1 = try privateDecoder.readUInt32()
        let checkint2 = try privateDecoder.readUInt32()
        guard checkint1 == checkint2 else {
            throw SSHEd25519KeyImportError.checkintMismatch
        }
        let keyType = try privateDecoder.readString()
        guard keyType == "ssh-ed25519" else {
            throw SSHEd25519KeyImportError.unsupportedKeyType(keyType)
        }
        _ = try privateDecoder.readData() // public key raw (32 bytes) — redundant with the seed-derived key.
        let secretKeyField = try privateDecoder.readData()
        guard secretKeyField.count == 64 else {
            throw SSHEd25519KeyImportError.malformedSecretKeyField
        }

        // OpenSSH's ed25519 "private key" field is the 64-byte libsodium
        // secret key: the 32-byte seed followed by the 32-byte public key.
        return secretKeyField.prefix(32)
    }
}

/// Errors surfaced while importing an OpenSSH Ed25519 private key. Messages
/// never include key material.
enum SSHEd25519KeyImportError: Error, Sendable, Equatable, LocalizedError {
    case notPEMArmored
    case badMagic
    case encryptedKeyUnsupported
    case unsupportedKeyCount(Int)
    case checkintMismatch
    case unsupportedKeyType(String)
    case malformedSecretKeyField
    case truncated

    var errorDescription: String? {
        switch self {
        case .notPEMArmored:
            return "Not a PEM-armored OpenSSH private key."
        case .badMagic:
            return "Not an openssh-key-v1 private key."
        case .encryptedKeyUnsupported:
            return "Passphrase-protected SSH keys aren't supported here."
        case .unsupportedKeyCount(let count):
            return "Expected exactly one key in the file, found \(count)."
        case .checkintMismatch:
            return "SSH key data is corrupt (checkint mismatch)."
        case .unsupportedKeyType(let type):
            return "Only Ed25519 keys are supported (found \(type))."
        case .malformedSecretKeyField:
            return "SSH key data is corrupt (unexpected secret key length)."
        case .truncated:
            return "SSH key data is truncated."
        }
    }
}

/// Minimal big-endian SSH wire-format decoder (RFC 4251 §5), the inverse of
/// `SSHKeyGenerator`'s private `SSHWireEncoder`.
private struct SSHWireDecoder {
    private let data: Data
    private var offset: Data.Index

    init(data: Data) {
        self.data = data
        self.offset = data.startIndex
    }

    mutating func readUInt32() throws -> UInt32 {
        guard data.distance(from: offset, to: data.endIndex) >= 4 else {
            throw SSHEd25519KeyImportError.truncated
        }
        let bytes = data[offset..<data.index(offset, offsetBy: 4)]
        offset = data.index(offset, offsetBy: 4)
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    /// Reads a length-prefixed byte string (SSH wire `string`/generic `data`
    /// — the wire encoding is identical for both).
    mutating func readData() throws -> Data {
        let length = try Int(readUInt32())
        guard length >= 0, data.distance(from: offset, to: data.endIndex) >= length else {
            throw SSHEd25519KeyImportError.truncated
        }
        let result = data[offset..<data.index(offset, offsetBy: length)]
        offset = data.index(offset, offsetBy: length)
        return Data(result)
    }

    mutating func readString() throws -> String {
        let bytes = try readData()
        guard let string = String(data: bytes, encoding: .utf8) else {
            throw SSHEd25519KeyImportError.truncated
        }
        return string
    }
}
