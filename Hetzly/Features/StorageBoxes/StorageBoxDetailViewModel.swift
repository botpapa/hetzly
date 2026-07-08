import Foundation
import HetznerKit
import Observation

/// Drives `StorageBoxDetailView`: loads the box plus its snapshots and
/// subaccounts, and fires rename/access-settings/reset-password/
/// snapshot/subaccount actions.
///
/// Every mutating `StorageBoxClient` call returns a queued `Action` (not the
/// updated resource) — this follows the same "ActionTracker-lite" contract
/// `VolumeDetailView`/`NetworkDetailView` use for Cloud resources: fire the
/// call, then reload the affected list/resource, rather than polling the
/// action to completion.
///
/// Hetzner's Storage Box API also has no server-generated password to
/// reveal (unlike Robot's rescue/reset root password) — `resetPassword` and
/// `createSubaccount` both require the *caller* to supply a new password.
/// `StorageBoxPasswordGenerator` fills that gap; the generated value is
/// still only ever shown once, via `revealedPassword`, and never logged.
@MainActor
@Observable
final class StorageBoxDetailViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// A freshly generated password, shown exactly once via
    /// `SensitiveSecretCard` — either the box's own password (after a
    /// reset) or a new subaccount's initial password (after creation).
    struct RevealedPassword: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let subtitle: String?
        let password: String
    }

    let route: StorageBoxRoute

    private(set) var box: StorageBox?
    private(set) var loadState: LoadState = .idle

    private(set) var snapshots: [StorageBoxSnapshot] = []
    private(set) var snapshotsState: LoadState = .idle

    private(set) var subaccounts: [StorageBoxSubaccount] = []
    private(set) var subaccountsState: LoadState = .idle

    private(set) var isPerformingAction = false
    private(set) var actionError: String?
    private(set) var lastActionSuccessText: String?
    private(set) var lastActionSucceeded = false

    private(set) var revealedPassword: RevealedPassword?

    /// Every sub-resource this view model calls through to is present on
    /// F1's landed `StorageBoxClient` — kept `true` throughout, but exposed
    /// as flags (rather than inlined) so a future API regression can flip
    /// one to `false` and have the corresponding section render a quiet
    /// "not yet supported" caption instead of a broken call.
    private(set) var snapshotsSupported = true
    private(set) var subaccountsSupported = true
    private(set) var accessSettingsSupported = true
    private(set) var resetPasswordSupported = true
    private(set) var renameSupported = true

    private let container: AppContainer

    init(route: StorageBoxRoute, container: AppContainer) {
        self.route = route
        self.container = container
    }

    private var client: StorageBoxClient? {
        container.storageBoxClient(for: route.accountID)
    }

    // MARK: - Loading

    func load() async {
        guard let client else {
            loadState = .failed("No stored token for this account.")
            return
        }
        if box == nil { loadState = .loading }
        do {
            let loaded = try await client.storageBox(id: route.storageBoxID)
            box = loaded
            loadState = .loaded
        } catch {
            loadState = .failed(Self.message(for: error))
        }
    }

    func loadSnapshots() async {
        guard snapshotsSupported, let client else { return }
        snapshotsState = .loading
        do {
            let loaded = try await client.listSnapshots(storageBoxID: route.storageBoxID)
            snapshots = loaded.sorted { $0.created > $1.created }
            snapshotsState = .loaded
        } catch {
            snapshotsState = .failed(Self.message(for: error))
        }
    }

    func loadSubaccounts() async {
        guard subaccountsSupported, let client else { return }
        subaccountsState = .loading
        do {
            subaccounts = try await client.listSubaccounts(storageBoxID: route.storageBoxID)
            subaccountsState = .loaded
        } catch {
            subaccountsState = .failed(Self.message(for: error))
        }
    }

    func acknowledgeSuccess() {
        lastActionSucceeded = false
    }

    func dismissRevealedPassword() {
        revealedPassword = nil
    }

    // MARK: - Rename

    @discardableResult
    func rename(to newName: String) async -> Bool {
        guard renameSupported, let client else { return false }
        isPerformingAction = true
        actionError = nil
        defer { isPerformingAction = false }
        do {
            box = try await client.updateStorageBox(id: route.storageBoxID, name: newName)
            return true
        } catch {
            actionError = Self.message(for: error)
            return false
        }
    }

    // MARK: - Access settings

    /// Sends only the one flag that changed — `updateAccessSettings` treats
    /// every other (nil) parameter as "leave unchanged" server-side — then
    /// reloads the box so `settings` reflects the queued action's effect.
    func updateAccessSetting(_ proto: StorageBoxAccessProtocol, enabled: Bool) {
        guard accessSettingsSupported, let client, !isPerformingAction else { return }
        isPerformingAction = true
        actionError = nil
        lastActionSucceeded = false
        let boxID = route.storageBoxID
        Task { [weak self] in
            do {
                _ = try await client.updateAccessSettings(
                    id: boxID,
                    reachableExternally: proto == .reachableExternally ? enabled : nil,
                    sambaEnabled: proto == .samba ? enabled : nil,
                    sshEnabled: proto == .ssh ? enabled : nil,
                    webdavEnabled: proto == .webdav ? enabled : nil
                )
                self?.lastActionSuccessText = "Access settings updated."
                self?.lastActionSucceeded = true
                await self?.load()
            } catch {
                self?.actionError = Self.message(for: error)
            }
            self?.isPerformingAction = false
        }
    }

    // MARK: - Reset password

    /// Generates a strong password client-side (Hetzner's API requires the
    /// caller to supply the new password — there's nothing server-generated
    /// to fetch) and reveals it once the reset action is accepted.
    func resetPassword() {
        guard resetPasswordSupported, let client, !isPerformingAction else { return }
        isPerformingAction = true
        actionError = nil
        lastActionSucceeded = false
        let boxID = route.storageBoxID
        let newPassword = StorageBoxPasswordGenerator.generate()
        Task { [weak self] in
            do {
                _ = try await client.resetPassword(id: boxID, newPassword: newPassword)
                self?.revealedPassword = RevealedPassword(
                    title: "New Storage Box Password", subtitle: self?.box?.username, password: newPassword
                )
                self?.lastActionSuccessText = "Password reset."
                self?.lastActionSucceeded = true
            } catch {
                self?.actionError = Self.message(for: error)
            }
            self?.isPerformingAction = false
        }
    }

    // MARK: - Snapshots

    func createSnapshot(description: String?) {
        guard snapshotsSupported, let client, !isPerformingAction else { return }
        isPerformingAction = true
        actionError = nil
        lastActionSucceeded = false
        let boxID = route.storageBoxID
        Task { [weak self] in
            do {
                _ = try await client.createSnapshot(storageBoxID: boxID, description: description)
                self?.lastActionSuccessText = "Snapshot created."
                self?.lastActionSucceeded = true
                await self?.loadSnapshots()
            } catch {
                self?.actionError = Self.message(for: error)
            }
            self?.isPerformingAction = false
        }
    }

    func deleteSnapshot(_ snapshot: StorageBoxSnapshot) {
        guard snapshotsSupported, let client, !isPerformingAction else { return }
        isPerformingAction = true
        actionError = nil
        lastActionSucceeded = false
        let boxID = route.storageBoxID
        Task { [weak self] in
            do {
                _ = try await client.deleteSnapshot(storageBoxID: boxID, id: snapshot.id)
                self?.lastActionSuccessText = "Snapshot deleted."
                self?.lastActionSucceeded = true
                await self?.loadSnapshots()
            } catch {
                self?.actionError = Self.message(for: error)
            }
            self?.isPerformingAction = false
        }
    }

    // MARK: - Subaccounts

    /// Generates the subaccount's initial password client-side (same
    /// caller-supplies-the-password constraint as `resetPassword()`) and
    /// reveals it once creation succeeds.
    func createSubaccount(
        homeDirectory: String,
        name: String?,
        description: String?,
        accessSettings: StorageBoxSubaccountAccessSettings
    ) {
        guard subaccountsSupported, let client, !isPerformingAction else { return }
        isPerformingAction = true
        actionError = nil
        lastActionSucceeded = false
        let boxID = route.storageBoxID
        let newPassword = StorageBoxPasswordGenerator.generate()
        Task { [weak self] in
            do {
                let result = try await client.createSubaccount(
                    storageBoxID: boxID,
                    homeDirectory: homeDirectory,
                    password: newPassword,
                    name: name,
                    description: description,
                    accessSettings: accessSettings
                )
                self?.revealedPassword = RevealedPassword(
                    title: "New Subaccount Password", subtitle: result.subaccount.username, password: newPassword
                )
                self?.lastActionSuccessText = "Subaccount created."
                self?.lastActionSucceeded = true
                await self?.loadSubaccounts()
            } catch {
                self?.actionError = Self.message(for: error)
            }
            self?.isPerformingAction = false
        }
    }

    func deleteSubaccount(_ subaccount: StorageBoxSubaccount) {
        guard subaccountsSupported, let client, !isPerformingAction else { return }
        isPerformingAction = true
        actionError = nil
        lastActionSucceeded = false
        let boxID = route.storageBoxID
        Task { [weak self] in
            do {
                _ = try await client.deleteSubaccount(storageBoxID: boxID, id: subaccount.id)
                self?.lastActionSuccessText = "Subaccount deleted."
                self?.lastActionSucceeded = true
                await self?.loadSubaccounts()
            } catch {
                self?.actionError = Self.message(for: error)
            }
            self?.isPerformingAction = false
        }
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? HetznerAPIError {
            return apiError.userMessage
        }
        return "Something went wrong. Please try again."
    }
}
