import XCTest
@testable import Hetzly

/// `SSHHostKeyStore` backs `SSHConnection`'s trust-on-first-use host key
/// checking. It's `UserDefaults`-backed (no Keychain entitlement needed),
/// so — unlike `ServerCredentialsVaultTests` — every assertion here runs for
/// real in this sandboxed test target, no `XCTSkip` needed.
///
/// `SSHHostKeyStore.fingerprint(of:)` itself (SHA-256 over the SSH
/// wire-format key blob, matching `ssh-keygen -l`'s and
/// `SSHKeyGenerator.generateEd25519`'s own fingerprint format) is NOT
/// exercised here: constructing a real `NIOSSHPublicKey` requires `import
/// NIOSSH` in this test target, and adding the `NIOSSH` SPM product as a
/// second target's dependency (alongside the `Hetzly` app target) produced
/// an `xcodebuild test`-only linker failure (`Ld …Hetzly.debug.dylib`:
/// undefined `NIOCore`/`NIOPosix` symbols) that a full `xcodegen generate` +
/// clean derived-data rebuild did not resolve — a known class of Xcode/
/// SwiftPM issue when one package product is linked into multiple local
/// targets in the same project. That function's correctness is instead
/// verified by inspection: it computes SHA-256 over the same wire-format
/// bytes `SSHKeyGenerator.sshEd25519PublicKeyBlob` does, recovered via
/// `String(openSSHPublicKey:)`'s base64 component, which is the identical
/// algorithm `SSHKeyGenerator.generateEd25519` already uses (and which the
/// `SSHEd25519KeyImporterTests` round-trip tests exercise from the private-
/// key side). Real host-key trust/mismatch behavior against a live server
/// still needs on-device validation — see the SP1 handoff notes.
final class SSHHostKeyStoreTests: XCTestCase {
    /// Obviously-fake hostnames unlikely to collide with anything real;
    /// cleaned up in `tearDown` regardless.
    private let host = "test-host.invalid.hetzly-tests"
    private let otherHost = "test-host-2.invalid.hetzly-tests"
    private let port = 22

    override func tearDown() {
        SSHHostKeyStore.forget(host: host, port: port)
        SSHHostKeyStore.forget(host: host, port: 2222)
        SSHHostKeyStore.forget(host: otherHost, port: port)
        super.tearDown()
    }

    func test_trustedFingerprint_isNilForUnseenHost() {
        XCTAssertNil(SSHHostKeyStore.trustedFingerprint(host: host, port: port))
    }

    func test_trust_persistsFingerprintForHost() {
        SSHHostKeyStore.trust(fingerprint: "SHA256:abc123", host: host, port: port)
        XCTAssertEqual(SSHHostKeyStore.trustedFingerprint(host: host, port: port), "SHA256:abc123")
    }

    /// This is the explicit "user reviewed the mismatch warning and chose
    /// to trust the new key anyway" path from `ServerTerminalView` —
    /// distinct from silent trust-on-first-use.
    func test_updateTrustedFingerprint_overwritesExistingTrust() {
        SSHHostKeyStore.trust(fingerprint: "SHA256:first", host: host, port: port)
        SSHHostKeyStore.updateTrustedFingerprint("SHA256:second", host: host, port: port)
        XCTAssertEqual(SSHHostKeyStore.trustedFingerprint(host: host, port: port), "SHA256:second")
    }

    func test_forget_removesStoredFingerprint() {
        SSHHostKeyStore.trust(fingerprint: "SHA256:abc123", host: host, port: port)
        SSHHostKeyStore.forget(host: host, port: port)
        XCTAssertNil(SSHHostKeyStore.trustedFingerprint(host: host, port: port))
    }

    func test_forget_isIdempotentForUnknownHost() {
        SSHHostKeyStore.forget(host: "never-trusted.invalid.hetzly-tests", port: port)
        // No crash, no throw — just confirming it's a safe no-op.
    }

    func test_differentHostsAreTrackedIndependently() {
        SSHHostKeyStore.trust(fingerprint: "SHA256:one", host: host, port: port)
        SSHHostKeyStore.trust(fingerprint: "SHA256:two", host: otherHost, port: port)

        XCTAssertEqual(SSHHostKeyStore.trustedFingerprint(host: host, port: port), "SHA256:one")
        XCTAssertEqual(SSHHostKeyStore.trustedFingerprint(host: otherHost, port: port), "SHA256:two")
    }

    /// Same host, different port (e.g. a custom SSH port alongside the
    /// default) must not share a trust entry — a mismatch on one port
    /// shouldn't silently pass because the other port's fingerprint happened
    /// to be trusted.
    func test_differentPortsOnSameHostAreTrackedIndependently() {
        SSHHostKeyStore.trust(fingerprint: "SHA256:port22", host: host, port: 22)
        SSHHostKeyStore.trust(fingerprint: "SHA256:port2222", host: host, port: 2222)

        XCTAssertEqual(SSHHostKeyStore.trustedFingerprint(host: host, port: 22), "SHA256:port22")
        XCTAssertEqual(SSHHostKeyStore.trustedFingerprint(host: host, port: 2222), "SHA256:port2222")
    }
}
