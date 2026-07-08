import Foundation

/// Builds `hetzly://` deep-link URLs for widget tap targets. Intentionally
/// duplicates the tiny bit of URL-shape knowledge from
/// `Hetzly/App/DeepLink.swift` (which does the parsing, app-side) rather
/// than sharing a file across targets — `HetzlyWidgets` doesn't depend on
/// the `Hetzly` app target, and a handful of URL string literals isn't
/// worth adding a new shared-sources entry in project.yml for.
enum WidgetDeepLink {
    /// The small "Status" widget and the "Top servers" widget's own
    /// background (outside any per-row `Link`) both just open the
    /// dashboard — neither carries a single obvious "the" destination.
    static let dashboard: URL = url("hetzly://dashboard")

    /// A specific server, when the snapshot row carries both ids — falls
    /// back to `dashboard` (via the caller) when it doesn't.
    static func server(projectID: UUID, serverID: Int) -> URL {
        url("hetzly://server/\(projectID.uuidString)/\(serverID)")
    }

    /// Parses `string` into a `URL`, falling back to a harmless local path
    /// rather than force-unwrapping — both inputs here are either compile-time
    /// literals or a `UUID.uuidString`/`Int` interpolation, so the fallback
    /// is unreachable in practice, but this keeps the file free of `!`.
    private static func url(_ string: String) -> URL {
        URL(string: string) ?? URL(fileURLWithPath: "/")
    }
}
