import Foundation
import NIOCore
import NIOSSH

/// Offers a single password once, then gives up. swift-nio-ssh calls
/// `nextAuthenticationType` again after a rejected offer (to let a client
/// try a different method); returning `nil` there tells it we have nothing
/// else to try, which is how `SSHConnection` detects "authentication
/// exhausted" via `didExhaustAuthentication`.
///
/// - Important: `password` is held only in memory for the lifetime of the
///   connection attempt and is never logged.
final class SSHPasswordAuthDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let username: String
    private let password: String
    private let lock = NSLock()
    private var didOffer = false

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    /// `true` once this delegate has offered its one credential and been
    /// asked again (i.e. the server rejected it and there's nothing left to
    /// try).
    var didExhaustAuthentication: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didOffer
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        lock.lock()
        let alreadyOffered = didOffer
        didOffer = true
        lock.unlock()

        guard !alreadyOffered, availableMethods.contains(.password) else {
            nextChallengePromise.succeed(nil)
            return
        }
        nextChallengePromise.succeed(
            NIOSSHUserAuthenticationOffer(
                username: username,
                serviceName: "ssh-connection",
                offer: .password(.init(password: password))
            )
        )
    }
}

/// Offers a single private-key credential once, then gives up. Same
/// exhaustion-detection shape as `SSHPasswordAuthDelegate`.
final class SSHPrivateKeyAuthDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let username: String
    private let privateKey: NIOSSHPrivateKey
    private let lock = NSLock()
    private var didOffer = false

    init(username: String, privateKey: NIOSSHPrivateKey) {
        self.username = username
        self.privateKey = privateKey
    }

    var didExhaustAuthentication: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didOffer
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        lock.lock()
        let alreadyOffered = didOffer
        didOffer = true
        lock.unlock()

        guard !alreadyOffered, availableMethods.contains(.publicKey) else {
            nextChallengePromise.succeed(nil)
            return
        }
        nextChallengePromise.succeed(
            NIOSSHUserAuthenticationOffer(
                username: username,
                serviceName: "ssh-connection",
                offer: .privateKey(.init(privateKey: privateKey))
            )
        )
    }
}

/// Trust-on-first-use host key validation, backed by `SSHHostKeyStore`. See
/// that type's doc comment for the persisted-fingerprint-only rationale.
///
/// swift-nio-ssh's `validateHostKey` only lets us succeed or fail a promise
/// — it doesn't propagate a typed reason back to the caller of
/// `connect()`. So on mismatch this both fails the promise (tearing down the
/// SSH handshake, which is the security-relevant part) AND records the two
/// fingerprints on `self`, which `SSHConnection.connect` reads back out
/// after the connection attempt fails to decide whether to report
/// `.hostKeyMismatch` specifically.
final class SSHTrustOnFirstUseHostKeyDelegate: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    let host: String
    let port: Int
    private let lock = NSLock()
    private var recordedMismatch: (expected: String, received: String)?

    init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    var mismatch: (expected: String, received: String)? {
        lock.lock()
        defer { lock.unlock() }
        return recordedMismatch
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let fingerprint = SSHHostKeyStore.fingerprint(of: hostKey)

        if let trusted = SSHHostKeyStore.trustedFingerprint(host: host, port: port) {
            guard trusted == fingerprint else {
                lock.lock()
                recordedMismatch = (expected: trusted, received: fingerprint)
                lock.unlock()
                validationCompletePromise.fail(
                    SSHConnectionError.hostKeyMismatch(host: host, expected: trusted, received: fingerprint)
                )
                return
            }
            validationCompletePromise.succeed(())
        } else {
            // Trust on first use.
            SSHHostKeyStore.trust(fingerprint: fingerprint, host: host, port: port)
            validationCompletePromise.succeed(())
        }
    }
}
