import Foundation
import HetznerKit
import Observation

/// Drives `DNSZoneListView`: loads/creates/deletes DNS zones for the
/// currently selected project.
@MainActor
@Observable
final class DNSZoneListViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var zones: [DNSZone] = []
    private(set) var loadState: LoadState = .idle
    private(set) var deletionError: String?

    let projectID: UUID
    private let container: AppContainer

    init(projectID: UUID, container: AppContainer) {
        self.projectID = projectID
        self.container = container
    }

    private var client: CloudClient? { container.cloudClient(for: projectID) }

    func load() async {
        guard let client else {
            loadState = .failed("No stored credentials for this project.")
            return
        }
        if zones.isEmpty { loadState = .loading }
        do {
            zones = try await client.listZones().sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            loadState = .loaded
        } catch {
            loadState = .failed(Self.message(for: error))
        }
    }

    func create(name: String, ttl: Int?) async -> Result<DNSZone, DisplayError> {
        guard let client else { return .failure(DisplayError("No stored credentials for this project.")) }
        do {
            let created = try await client.createZone(name: name, ttl: ttl)
            zones.append(created.zone)
            zones.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return .success(created.zone)
        } catch {
            return .failure(DisplayError(Self.message(for: error)))
        }
    }

    func delete(_ zone: DNSZone) async {
        guard let client else { return }
        deletionError = nil
        do {
            try await client.deleteZone(id: zone.id)
            zones.removeAll { $0.id == zone.id }
        } catch {
            deletionError = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        (error as? HetznerAPIError)?.userMessage ?? "Something went wrong. Please try again."
    }
}
