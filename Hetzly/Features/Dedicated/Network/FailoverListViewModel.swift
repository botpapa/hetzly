import Foundation
import HetznerKit
import Observation

/// Drives `FailoverListView`: loads Robot failover IPs for the selected
/// account. No auto-refresh, no background polling — mirrors
/// `VSwitchListViewModel`/`DedicatedListViewModel`.
@MainActor
@Observable
final class FailoverListViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var failoverIPs: [RobotFailover] = []
    private(set) var loadState: LoadState = .idle

    func load(accountID: UUID?, container: AppContainer) async {
        guard let accountID else {
            failoverIPs = []
            loadState = .idle
            return
        }
        guard let client = container.robotClient(for: accountID) else {
            failoverIPs = []
            loadState = .failed("No stored credentials for this account.")
            return
        }
        if failoverIPs.isEmpty { loadState = .loading }
        do {
            let loaded = try await client.listFailoverIPs()
            failoverIPs = loaded.sorted { $0.ip.localizedStandardCompare($1.ip) == .orderedAscending }
            loadState = .loaded
        } catch {
            loadState = .failed(Self.message(for: error))
        }
    }

    static func message(for error: Error) -> String {
        if let apiError = error as? HetznerAPIError {
            return apiError.userMessage
        }
        return "Something went wrong. Please try again."
    }
}
