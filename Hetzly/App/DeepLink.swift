import Foundation

/// A parsed `hetzly://` URL — the in-app destination it names, independent
/// of how it arrived (system `onOpenURL`, a widget tap, a Shortcut, or a
/// UI test's launch-environment bridge; see `HetzlyApp`).
///
/// Routes (all lowercase host, matching URL scheme conventions):
/// - `hetzly://server/<projectID>/<serverID>` → `.server(ServerRoute)`
/// - `hetzly://project/<projectID>` → `.project(ProjectRoute)`
/// - `hetzly://dashboard` → `.dashboard`
/// - `hetzly://costs` → `.costs`
enum DeepLink: Hashable, Sendable {
    case server(ServerRoute)
    case project(ProjectRoute)
    case dashboard
    case costs
}

/// Parses a `URL` into a `DeepLink`, or `nil` if it isn't a recognized
/// `hetzly://` route. Never throws — an unrecognized or malformed URL is
/// just ignored by whoever calls this (`onOpenURL` silently no-ops), which
/// is the right behavior for a URL scheme handler: a stale Shortcut or a
/// widget built against a future route shape should never crash the app.
enum DeepLinkParser {
    static let scheme = "hetzly"

    static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        guard let host = url.host?.lowercased() else { return nil }

        // `url.pathComponents` includes a leading "/" as its own element
        // (e.g. "/abc/123" → ["/", "abc", "123"]) — strip it so callers work
        // with plain path segments.
        let segments = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "server":
            guard segments.count >= 2,
                  let projectID = UUID(uuidString: segments[0]),
                  let serverID = Int(segments[1])
            else { return nil }
            return .server(ServerRoute(projectID: projectID, serverID: serverID))

        case "project":
            guard let first = segments.first, let projectID = UUID(uuidString: first) else { return nil }
            return .project(ProjectRoute(projectID: projectID))

        case "dashboard":
            return .dashboard

        case "costs":
            return .costs

        default:
            return nil
        }
    }
}
