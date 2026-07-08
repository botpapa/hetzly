import Foundation
import HetznerKit
import Observation

/// Drives `FirewallListView`: loads/creates/deletes firewalls for the
/// currently selected project.
@MainActor
@Observable
final class FirewallListViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var firewalls: [Firewall] = []
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
        if firewalls.isEmpty { loadState = .loading }
        do {
            firewalls = try await client.listFirewalls().sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            loadState = .loaded
        } catch {
            loadState = .failed(Self.message(for: error))
        }
    }

    func create(name: String) async -> Result<Firewall, DisplayError> {
        guard let client else { return .failure(DisplayError("No stored credentials for this project.")) }
        do {
            let created = try await client.createFirewall(name: name)
            firewalls.append(created.firewall)
            firewalls.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return .success(created.firewall)
        } catch {
            return .failure(DisplayError(Self.message(for: error)))
        }
    }

    func delete(_ firewall: Firewall) async {
        guard let client else { return }
        deletionError = nil
        do {
            try await client.deleteFirewall(id: firewall.id)
            firewalls.removeAll { $0.id == firewall.id }
        } catch {
            deletionError = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        (error as? HetznerAPIError)?.userMessage ?? "Something went wrong. Please try again."
    }
}
