import Foundation

/// How `ServerTerminalView` should authenticate to the remote SSH server.
///
/// This is the binding entry point worker SP2 constructs against (see
/// `CONTRACTS.md` → "Server-page wave contracts → Terminal module (SP1)").
/// SP2 resolves one of these from, in order: a stored SSH private key for a
/// key present on the server, then `ServerCredentialsVault`'s saved root
/// password, then a user prompt.
enum SSHCredential: Sendable {
    /// An OpenSSH `openssh-key-v1` PEM-armored private key, exactly the
    /// format `SSHKeyGenerator.generateEd25519` produces and
    /// `SSHKeyGenerator.loadPrivateKey` returns. See
    /// `SSHEd25519KeyImporter` for how this is turned into something
    /// swift-nio-ssh can sign with.
    case privateKeyPEM(String)
    /// A plaintext password, as saved by `ServerCredentialsVault` or typed
    /// by the user. Never logged; held only in memory for the lifetime of
    /// the connection attempt.
    case password(String)
}
