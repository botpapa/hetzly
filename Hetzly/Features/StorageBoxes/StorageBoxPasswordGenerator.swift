import Foundation
import Security

/// Generates strong passwords client-side for Storage Box / subaccount
/// password resets.
///
/// Unlike Robot's rescue/reset flows (where Hetzner generates and returns a
/// one-time root password), the Storage Box API's `resetPassword`/
/// `createSubaccount` actions require the *caller* to supply the new
/// password (`StorageBoxClient.resetPassword(id:newPassword:)`,
/// `.createSubaccount(...password:...)`) — there is no server-generated
/// value to reveal. This type fills that gap so the UI can still offer a
/// one-tap "generate a strong password" affordance that satisfies Hetzner's
/// documented policy (>=12 characters, at least one special character).
enum StorageBoxPasswordGenerator {
    private static let lowercase = Array("abcdefghijkmnopqrstuvwxyz")
    private static let uppercase = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
    private static let digits = Array("23456789")
    private static let symbols = Array("!@#$%^&*-_=+?")

    /// Generates a 20-character password drawing from all four character
    /// classes, using `SecRandomCopyBytes` (the same cryptographic RNG
    /// `KeychainStore` implicitly relies on via Security.framework) rather
    /// than `Int.random`'s non-cryptographic default generator.
    static func generate(length: Int = 20) -> String {
        let pools = [lowercase, uppercase, digits, symbols]
        var characters: [Character] = pools.map { pool in pool[secureRandomIndex(upperBound: pool.count)] }

        let allCharacters = pools.flatMap { $0 }
        while characters.count < length {
            characters.append(allCharacters[secureRandomIndex(upperBound: allCharacters.count)])
        }

        var rng = SecureShuffleGenerator()
        return String(characters.shuffled(using: &rng))
    }

    private static func secureRandomIndex(upperBound: Int) -> Int {
        var byte: UInt8 = 0
        let status = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
        guard status == errSecSuccess else {
            // Security.framework's own RNG failing is effectively
            // unreachable on-device; fall back to the system generator
            // rather than crashing (no `fatalError`/`try!` in app code).
            return Int.random(in: 0..<upperBound)
        }
        return Int(byte) % upperBound
    }
}

/// A `RandomNumberGenerator` backed by `SecRandomCopyBytes`, so
/// `shuffled(using:)` doesn't fall back to the non-cryptographic default
/// generator for the final ordering step.
private struct SecureShuffleGenerator: RandomNumberGenerator {
    mutating func next() -> UInt64 {
        var value: UInt64 = 0
        let status = withUnsafeMutableBytes(of: &value) { pointer -> OSStatus in
            guard let baseAddress = pointer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, pointer.count, baseAddress)
        }
        guard status == errSecSuccess else {
            return UInt64.random(in: .min ... .max)
        }
        return value
    }
}
