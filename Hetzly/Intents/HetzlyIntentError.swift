import Foundation

/// Human-readable failures surfaced by `Hetzly/Intents/` — never a raw
/// `HetznerAPIError`, SwiftData error, or Keychain status code. AppIntents
/// (Shortcuts/Siri) presents `errorDescription` directly as the failure
/// dialog, so every case here reads as a complete sentence a user can act on.
enum HetzlyIntentError: LocalizedError {
    /// No `ProjectRecord` exists at all — nothing to look up or reboot.
    case noProjects
    /// A project exists but has no Keychain-stored Cloud API token.
    case needsToken(projectName: String)
    /// A project has servers but none of them have billable cost items
    /// (e.g. every fetch failed, or pricing didn't match any server type).
    case noBillableResources
    /// A `HetznerAPIError.userMessage` (already a human sentence) wrapped so
    /// call sites have one error type to throw.
    case api(String)
    /// Generic network/transport failure that isn't a `HetznerAPIError`.
    case unreachable

    var errorDescription: String? {
        switch self {
        case .noProjects:
            "Add a Hetzner project in Hetzly first, then try again."
        case .needsToken(let projectName):
            "\(projectName) needs an API token — open Hetzly and add one in Settings."
        case .noBillableResources:
            "No billable resources found yet. Open Hetzly to check your projects."
        case .api(let message):
            message
        case .unreachable:
            "Couldn't reach Hetzner right now. Check your connection and try again."
        }
    }
}
