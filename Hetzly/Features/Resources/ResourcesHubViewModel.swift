import Foundation
import HetznerKit
import Observation

/// Drives `ResourcesHubView`: lazily loads a per-category item count for the
/// currently-selected project so the hub's rows can show a badge without
/// each row screen having already been visited.
///
/// Counts are fetched with `async let` (not a `TaskGroup`) so everything
/// stays on `@MainActor` — this type never touches concurrency isolation
/// beyond what the `CloudClient` actor itself already provides.
@MainActor
@Observable
final class ResourcesHubViewModel {
    struct Counts: Equatable {
        var volumes: Int?
        var networks: Int?
        var primaryIPs: Int?
        var floatingIPs: Int?
        var sshKeys: Int?
        var certificates: Int?
        var placementGroups: Int?
    }

    private(set) var counts = Counts()
    private(set) var errorMessage: String?
    private(set) var isLoading = false

    private var loadedProjectID: UUID?

    func loadIfNeeded(projectID: UUID?, container: AppContainer) async {
        guard projectID != loadedProjectID else { return }
        await load(projectID: projectID, container: container)
    }

    func load(projectID: UUID?, container: AppContainer) async {
        loadedProjectID = projectID

        guard let projectID, let client = container.cloudClient(for: projectID) else {
            counts = Counts()
            errorMessage = projectID == nil ? nil : "No stored credentials for this project."
            return
        }

        isLoading = true
        errorMessage = nil

        async let volumes = try? client.listVolumes()
        async let networks = try? client.listNetworks()
        async let primaryIPs = try? client.listPrimaryIPs()
        async let floatingIPs = try? client.listFloatingIPs()
        async let sshKeys = try? client.listSSHKeys()
        async let certificates = try? client.listCertificates()
        async let placementGroups = try? client.listPlacementGroups()

        let (loadedVolumes, loadedNetworks, loadedPrimaryIPs, loadedFloatingIPs, loadedSSHKeys, loadedCertificates, loadedPlacementGroups) =
            await (volumes, networks, primaryIPs, floatingIPs, sshKeys, certificates, placementGroups)

        counts = Counts(
            volumes: loadedVolumes?.count,
            networks: loadedNetworks?.count,
            primaryIPs: loadedPrimaryIPs?.count,
            floatingIPs: loadedFloatingIPs?.count,
            sshKeys: loadedSSHKeys?.count,
            certificates: loadedCertificates?.count,
            placementGroups: loadedPlacementGroups?.count
        )
        isLoading = false
    }
}
