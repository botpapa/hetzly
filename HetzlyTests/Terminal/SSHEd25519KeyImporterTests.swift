import Crypto
import NIOSSH
import XCTest
@testable import Hetzly

/// `SSHEd25519KeyImporter` is the one piece of the Terminal module (SP1)
/// that's fully unit-testable without a live SSH server: it's a pure
/// byte-parsing function over the exact OpenSSH-PEM format
/// `SSHKeyGenerator` already produces and this test suite can generate
/// on-device without any network or Keychain entitlement.
///
/// The core claim under test: round-tripping a freshly generated key through
/// `ed25519Seed(fromOpenSSHPEM:)`/`importPrivateKey(fromOpenSSHPEM:)`
/// recovers the exact same key `SSHKeyGenerator` started from — verified by
/// comparing derived public keys (a mismatched seed would produce a
/// different public key with overwhelming probability).
final class SSHEd25519KeyImporterTests: XCTestCase {
    func test_ed25519Seed_isAlways32Bytes() throws {
        let generated = SSHKeyGenerator.generateEd25519(comment: "tester@hetzly")
        let seed = try SSHEd25519KeyImporter.ed25519Seed(fromOpenSSHPEM: generated.privateKeyOpenSSH)
        XCTAssertEqual(seed.count, 32)
    }

    func test_ed25519Seed_roundTripsThroughGeneratedKey() throws {
        let generated = SSHKeyGenerator.generateEd25519(comment: "tester@hetzly")

        let seed = try SSHEd25519KeyImporter.ed25519Seed(fromOpenSSHPEM: generated.privateKeyOpenSSH)
        let rebuiltPrivateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        let rebuiltPublicKey = NIOSSHPrivateKey(ed25519Key: rebuiltPrivateKey).publicKey

        let originalPublicKey = try NIOSSHPublicKey(openSSHPublicKey: generated.publicKeyOpenSSH)

        XCTAssertEqual(String(openSSHPublicKey: rebuiltPublicKey), String(openSSHPublicKey: originalPublicKey))
    }

    func test_importPrivateKey_producesMatchingNIOSSHPublicKey() throws {
        let generated = SSHKeyGenerator.generateEd25519(comment: "tester@hetzly")

        let imported = try SSHEd25519KeyImporter.importPrivateKey(fromOpenSSHPEM: generated.privateKeyOpenSSH)
        let originalPublicKey = try NIOSSHPublicKey(openSSHPublicKey: generated.publicKeyOpenSSH)

        XCTAssertEqual(String(openSSHPublicKey: imported.publicKey), String(openSSHPublicKey: originalPublicKey))
    }

    /// Two separately generated keys must decode to two different seeds —
    /// guards against a degenerate parser that always returns the same
    /// fixed slice regardless of input.
    func test_ed25519Seed_differsAcrossDistinctGeneratedKeys() throws {
        let first = SSHKeyGenerator.generateEd25519(comment: "one")
        let second = SSHKeyGenerator.generateEd25519(comment: "two")

        let firstSeed = try SSHEd25519KeyImporter.ed25519Seed(fromOpenSSHPEM: first.privateKeyOpenSSH)
        let secondSeed = try SSHEd25519KeyImporter.ed25519Seed(fromOpenSSHPEM: second.privateKeyOpenSSH)

        XCTAssertNotEqual(firstSeed, secondSeed)
    }

    /// Not valid base64 at all (contains `!`, outside the base64 alphabet).
    func test_ed25519Seed_throwsOnInvalidBase64() {
        XCTAssertThrowsError(try SSHEd25519KeyImporter.ed25519Seed(fromOpenSSHPEM: "not a key at all!!!")) { error in
            XCTAssertEqual(error as? SSHEd25519KeyImportError, .notPEMArmored)
        }
    }

    /// Valid base64 (so it decodes cleanly) but not `openssh-key-v1` data —
    /// covered separately by `test_ed25519Seed_throwsOnWrongMagic`, which
    /// pins the specific `.badMagic` error for well-formed-but-wrong-format
    /// input, as distinct from this not-base64-at-all case.
    func test_ed25519Seed_throwsOnPlausibleButWrongBase64() {
        XCTAssertThrowsError(try SSHEd25519KeyImporter.ed25519Seed(fromOpenSSHPEM: "notakeyatall")) { error in
            XCTAssertEqual(error as? SSHEd25519KeyImportError, .badMagic)
        }
    }

    func test_ed25519Seed_throwsOnEmptyString() {
        XCTAssertThrowsError(try SSHEd25519KeyImporter.ed25519Seed(fromOpenSSHPEM: ""))
    }

    /// PEM-armored but not `openssh-key-v1` at all (e.g. a PKCS#8/PEM RSA
    /// key header) — must fail with a specific, non-crashing error rather
    /// than misparsing.
    func test_ed25519Seed_throwsOnWrongMagic() {
        let bogusBase64 = Data("not-openssh-key-v1-at-all".utf8).base64EncodedString()
        let pem = "-----BEGIN OPENSSH PRIVATE KEY-----\n\(bogusBase64)\n-----END OPENSSH PRIVATE KEY-----\n"
        XCTAssertThrowsError(try SSHEd25519KeyImporter.ed25519Seed(fromOpenSSHPEM: pem)) { error in
            XCTAssertEqual(error as? SSHEd25519KeyImportError, .badMagic)
        }
    }
}
