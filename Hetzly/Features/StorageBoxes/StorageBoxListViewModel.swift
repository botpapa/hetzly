import Foundation
import HetznerKit
import Observation

/// Drives `StorageBoxesView`'s list: loads Storage Boxes for the selected
/// account. Mirrors `DedicatedListViewModel`'s shape.
@MainActor
@Observable
final class StorageBoxListViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var boxes: [StorageBox] = []
    private(set) var loadState: LoadState = .idle

    func load(accountID: UUID?, container: AppContainer) async {
        guard let accountID else {
            boxes = []
            loadState = .idle
            return
        }
        guard let client = container.storageBoxClient(for: accountID) else {
            boxes = []
            loadState = .failed("No stored token for this account.")
            return
        }
        if boxes.isEmpty { loadState = .loading }
        do {
            let loaded = try await client.listStorageBoxes()
            boxes = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            loadState = .loaded
        } catch {
            loadState = .failed(Self.message(for: error))
        }
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? HetznerAPIError {
            return apiError.userMessage
        }
        return "Something went wrong. Please try again."
    }
}
