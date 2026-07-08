import Foundation
import LocalAuthentication

/// Gates access to sensitive UI (revealing tokens, copying rescue passwords,
/// etc.) behind Face ID / Touch ID, falling back to the device passcode.
///
/// A fresh `LAContext` is created for every attempt so state from a prior
/// evaluation never leaks into the next one. No secret material is ever
/// logged by this type.
@MainActor
final class BiometricGate {
    /// The human-readable message from the last failed evaluation, if any.
    /// Never contains secret material — only LocalAuthentication's own
    /// diagnostic text.
    private(set) var lastErrorMessage: String?

    init() {}

    /// Attempts device-owner authentication (biometrics with passcode
    /// fallback), showing `reason` to the user. Returns `true` only on
    /// successful authentication.
    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var policyError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            lastErrorMessage = policyError?.localizedDescription ?? "Device owner authentication is not available."
            return false
        }

        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if success {
                lastErrorMessage = nil
            } else {
                lastErrorMessage = "Authentication was not successful."
            }
            return success
        } catch {
            lastErrorMessage = (error as NSError).localizedDescription
            return false
        }
    }
}
