import Foundation

/// Centralized outbound links used across the app (About section, share
/// sheets, etc.) so there is exactly one place to update them before/after
/// publishing the repository publicly.
///
/// TODO(release): replace PLACEHOLDER-OWNER with the real GitHub org/user
/// once this repository has a public home, then update `privacyPolicyURL`
/// with a real hosted URL (see PUBLICATION-CHECKLIST.md).
enum AppLinks {
    /// The repository's GitHub URL. Falls back to `about:blank` rather than
    /// force-unwrapping if the literal ever fails to parse (it won't, but
    /// this keeps the app-target's "no force unwraps" rule honest).
    static let githubURL: URL = url(
        "https://github.com/PLACEHOLDER-OWNER/hetzly",
        fallback: "about:blank"
    )

    /// Hosted privacy-policy URL. Placeholder until publication — Hetzly
    /// collects no data (see SECURITY.md), but App Store submission still
    /// requires a reachable privacy-policy link.
    ///
    /// TODO(release): point this at a real hosted page before submitting to
    /// the App Store or publishing the repository.
    static let privacyPolicyURL: URL = url(
        "https://github.com/PLACEHOLDER-OWNER/hetzly/blob/main/SECURITY.md",
        fallback: "about:blank"
    )

    /// The mascot artist's storefront page, credited per the terms in
    /// ASSETS-LICENSE.md.
    static let mascotCreditURL: URL = url(
        "https://elthen.itch.io/2d-pixel-art-red-panda-sprites",
        fallback: "about:blank"
    )

    /// Parses `string` into a `URL`, falling back to a known-good literal
    /// rather than force-unwrapping. Both inputs are compile-time constants
    /// controlled by this file, so the fallback path is unreachable in
    /// practice — it exists purely so this file contains no `!`.
    private static func url(_ string: String, fallback: String) -> URL {
        URL(string: string) ?? URL(string: fallback) ?? URL(fileURLWithPath: "/")
    }
}
