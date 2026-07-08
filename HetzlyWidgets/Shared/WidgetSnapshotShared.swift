import Foundation

/// Compact snapshot of dashboard state, written by the app into the shared
/// App Group container and read back by the widget extension. Deliberately
/// minimal: no tokens, no IP addresses, nothing the extension shouldn't be
/// able to see. Defined once and compiled into both the `Hetzly` app target
/// and the `HetzlyWidgets` extension target so their JSON shapes can never
/// drift apart.
struct WidgetSnapshot: Codable, Sendable, Equatable {
    /// Per-server projection for the "Top servers" widget. `statusRaw`
    /// mirrors `HetznerKit.ServerStatus.rawValue` — kept as a plain string
    /// here so this file has no dependency on the package.
    struct ServerSummary: Codable, Sendable, Equatable {
        let name: String
        let statusRaw: String
        let cpuSamples: [Double]

        /// Identity for deep-linking this row straight to `ServerDetailView`
        /// via `hetzly://server/<projectID>/<serverID>` (see
        /// `TopServersWidgetEntryView`'s per-row `Link`). Both default to
        /// `nil` — as of this wave, `Hetzly/Store/WidgetSnapshotWriter.swift`
        /// (the only writer, out of scope for this worker) doesn't populate
        /// them yet, so every existing/decoded snapshot still round-trips
        /// fine and every row falls back to `hetzly://dashboard` until the
        /// writer is updated to fill these in.
        let projectID: UUID?
        let serverID: Int?

        init(name: String, statusRaw: String, cpuSamples: [Double], projectID: UUID? = nil, serverID: Int? = nil) {
            self.name = name
            self.statusRaw = statusRaw
            self.cpuSamples = cpuSamples
            self.projectID = projectID
            self.serverID = serverID
        }
    }

    let updatedAt: Date
    let totalServers: Int
    let runningServers: Int
    let attentionCount: Int
    /// Pre-formatted currency strings (e.g. "€18.42") — the widget never
    /// does its own currency math or locale formatting.
    let monthToDate: String?
    let projected: String?
    /// Up to 3 servers, ranked by CPU when sparkline data is available,
    /// otherwise the first 3 encountered.
    let topServers: [ServerSummary]
}

/// Reads/writes `WidgetSnapshot` to `widget-snapshot.json` inside the
/// `group.com.hetzly.app` App Group container. Both the app (writer) and the
/// widget extension (reader) go through this so the file name, App Group
/// ID, and JSON date strategy stay in exactly one place.
enum WidgetSnapshotIO {
    static let appGroupID = "group.com.hetzly.app"
    private static let fileName = "widget-snapshot.json"

    static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static func fileURL() -> URL? {
        containerURL()?.appendingPathComponent(fileName)
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL(), let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Returns `false` if the App Group container isn't reachable or the
    /// write failed — callers should treat that as a no-op, never a crash.
    @discardableResult
    static func save(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = fileURL() else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
