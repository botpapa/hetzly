import Foundation
import HetznerKit
import Observation

/// Drives `LoadBalancerListView`: loads and deletes load balancers for the
/// currently selected project.
@MainActor
@Observable
final class LoadBalancerListViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var loadBalancers: [LoadBalancer] = []
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
        if loadBalancers.isEmpty { loadState = .loading }
        do {
            loadBalancers = try await client.listLoadBalancers().sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            loadState = .loaded
        } catch {
            loadState = .failed(Self.message(for: error))
        }
    }

    func delete(_ loadBalancer: LoadBalancer) async {
        guard let client else { return }
        deletionError = nil
        do {
            try await client.deleteLoadBalancer(id: loadBalancer.id)
            loadBalancers.removeAll { $0.id == loadBalancer.id }
        } catch {
            deletionError = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        (error as? HetznerAPIError)?.userMessage ?? "Something went wrong. Please try again."
    }
}
