import Foundation
import HetznerKit

/// Lightweight per-row projection of a `Server` for dashboard display —
/// keeps the view layer decoupled from the full HetznerKit model and gives
/// rows a stable composite identity across projects (server IDs are only
/// guaranteed unique within a single Hetzner account/token, not globally
/// across every project a user has added).
struct ServerListItem: Identifiable, Sendable {
    let projectID: UUID
    let serverID: Int
    let name: String
    let status: ServerStatus
    let typeName: String
    let city: String
    let countryCode: String

    /// Primitive init — used by the view model when adapting `Server`
    /// values, and directly by previews so they don't need a live `Server`.
    init(
        projectID: UUID,
        serverID: Int,
        name: String,
        status: ServerStatus,
        typeName: String,
        city: String,
        countryCode: String
    ) {
        self.projectID = projectID
        self.serverID = serverID
        self.name = name
        self.status = status
        self.typeName = typeName
        self.city = city
        self.countryCode = countryCode
    }

    init(projectID: UUID, server: Server) {
        self.init(
            projectID: projectID,
            serverID: server.id,
            name: server.name,
            status: server.status,
            typeName: server.serverType.name,
            city: server.datacenter.location.city,
            countryCode: server.datacenter.location.country
        )
    }

    /// Composite ID: unique per project+server, also used as the CPU
    /// sparkline dictionary key.
    var id: String { "\(projectID.uuidString)#\(serverID)" }
}
