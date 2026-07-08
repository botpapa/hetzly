import Foundation
import HetznerKit

/// A rendered error message paired with typed recovery flags.
///
/// Every view model in the app used to catch an error and stash only its
/// `userMessage` `String` for display, which meant views could only offer
/// recovery affordances (e.g. an "Update token…" button) by re-parsing that
/// string — the Dashboard's `isAuthError(_:)` string-matched on "token was
/// rejected", which broke the moment `HetznerAPIError.userMessage`'s copy
/// changed. `DisplayableError` carries `HetznerAPIError.isAuthError` /
/// `.isPermissionError` alongside the message so call sites can branch on
/// the actual error type instead.
///
/// `message` mirrors what every call site already stored, so existing
/// `String`-based rendering keeps compiling with minimal churn — most call
/// sites only need to add a `.isAuthError` / `.isPermissionError` read
/// alongside their existing `.message` read.
struct DisplayableError: Equatable, Sendable {
    let message: String
    let isAuthError: Bool
    let isPermissionError: Bool

    /// Maps any thrown `Error` the way every view model's private
    /// `message(for:)` helper already did: a `HetznerAPIError` contributes
    /// its `userMessage` and flags, anything else falls back to a generic
    /// "Something went wrong" sentence with both flags `false`.
    init(_ error: Error) {
        if let apiError = error as? HetznerAPIError {
            message = apiError.userMessage
            isAuthError = apiError.isAuthError
            isPermissionError = apiError.isPermissionError
        } else {
            message = "Something went wrong. Please try again."
            isAuthError = false
            isPermissionError = false
        }
    }

    /// Direct constructor for call sites that already have a resolved
    /// message string (e.g. a "No token configured for this project."
    /// sentinel that isn't the result of catching a thrown `Error`).
    init(message: String, isAuthError: Bool = false, isPermissionError: Bool = false) {
        self.message = message
        self.isAuthError = isAuthError
        self.isPermissionError = isPermissionError
    }
}
