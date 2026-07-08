import Foundation
import HetznerKit
import Observation

/// Drives `VSwitchListView`: loads Robot vSwitches for the selected account.
/// No auto-refresh, no background polling — mirrors `DedicatedListViewModel`
/// exactly (only `load(...)` calls the view fires explicitly).
@MainActor
@Observable
final class VSwitchListViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var vSwitches: [RobotVSwitch] = []
    private(set) var loadState: LoadState = .idle

    func load(accountID: UUID?, container: AppContainer) async {
        guard let accountID else {
            vSwitches = []
            loadState = .idle
            return
        }
        guard let client = container.robotClient(for: accountID) else {
            vSwitches = []
            loadState = .failed("No stored credentials for this account.")
            return
        }
        if vSwitches.isEmpty { loadState = .loading }
        do {
            let loaded = try await client.listVSwitches()
            vSwitches = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
