import Foundation
import HetznerKit
import Observation

/// Drives `ServerDetailView`: loads the server, fires power actions and
/// tracks their progress via `ActionTracker`, and loads metrics for the
/// selected chart range.
@MainActor
@Observable
final class ServerDetailViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// A power/lifecycle action currently in flight, with the latest
    /// progress percentage reported by `ActionTracker`.
    struct ActiveAction: Equatable {
        let kind: PowerAction
        var progress: Int
    }

    /// A management action currently in flight. Unlike `ActiveAction`, the
    /// step label is a plain string rather than derived from the fixed
    /// `ServerManagementAction.progressVerb` — `runRescale`'s chained
    /// shutdown → resize → power-on flow relabels this per step even though
    /// it isn't a single `ServerManagementAction` case.
    struct ManagementActiveAction: Equatable {
        var stepLabel: String
        var progress: Int
    }

    /// A one-time secret (rescue/reset root password) surfaced by a
    /// management action, shown via `SensitiveSecretCard`. Never logged.
    struct RevealedSecret: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let secret: String
        let note: String
        /// `true` for the rescue password: the result sheet offers a
        /// chained "Reboot Now" since rescue only takes effect on reboot.
        var offersReboot = false
    }

    /// Console session credentials from `requestConsole`. `password` is a
    /// secret — never logged, shown only through `SensitiveSecretCard`.
    struct ConsoleCredentials: Identifiable, Equatable {
        let id = UUID()
        let wssURL: URL
        let password: String
    }

    let route: ServerRoute

    private(set) var server: Server?
    private(set) var loadState: LoadState = .idle

    private(set) var activeAction: ActiveAction?
    private(set) var actionError: String?
    /// `true` when `actionError` came from `HetznerAPIError.forbidden` — most
    /// commonly a Read-only token hitting a write endpoint. Drives the
    /// inline error card's "Update Token…" button; `actionError` itself
    /// already carries the read-only guidance sentence via
    /// `HetznerAPIError.userMessage`.
    private(set) var actionErrorIsPermissionError = false
    /// Flips to `true` right after an action finishes successfully, so the
    /// view can fire a one-shot success haptic / mascot celebration. The
    /// view is responsible for resetting it back to `false`.
    private(set) var lastActionSucceeded = false
    /// Which action last succeeded — read by the view to pick the success
    /// toast's copy and mascot state. Stays set after `lastActionSucceeded`
    /// resets so the toast can finish its exit animation.
    private(set) var lastSucceededAction: PowerAction?
    /// Set once a `delete` action completes, telling the view to pop back.
    private(set) var didDeleteServer = false

    // MARK: - Management actions (backups, rescue, snapshots, ISO, ...)

    private(set) var managementActiveAction: ManagementActiveAction?
    private(set) var managementActionError: String?
    /// Same rationale as `actionErrorIsPermissionError`, for management
    /// actions (backups, rescue, snapshots, ISO, rescale, ...).
    private(set) var managementActionErrorIsPermissionError = false
    private(set) var lastManagementActionSucceeded = false
    /// Success copy for the last completed management action or rescale
    /// step chain — read by the view for the success toast. Stays set after
    /// `lastManagementActionSucceeded` resets so the toast can finish its
    /// exit animation, mirroring `lastSucceededAction`.
    private(set) var lastManagementSuccessText: String?
    private(set) var revealedSecret: RevealedSecret?
    private(set) var consoleCredentials: ConsoleCredentials?
    /// The `Server` model has no `iso` field yet per CONTRACTS.md's binding
    /// shape, so there's no server-reported "what's attached right now"
    /// truth to read. This tracks the most recently attached ISO purely
    /// client-side (set on a successful `attachISO`, cleared on
    /// `detachISO`) so the ISO sheet can show attached/detach state within
    /// this session. It resets on relaunch and won't reflect ISOs attached
    /// from another device or the Hetzner console — a known limitation,
    /// flagged here and in the worker report rather than silently assumed.
    private(set) var locallyAttachedISO: ISO?

    // MARK: - Catalog data for management sheets

    private(set) var snapshots: [Image] = []
    private(set) var snapshotsState: LoadState = .idle

    private(set) var sshKeys: [SSHKey] = []
    private(set) var sshKeysState: LoadState = .idle

    private(set) var isos: [ISO] = []
    private(set) var isosState: LoadState = .idle

    private(set) var rebuildImages: [Image] = []
    private(set) var rebuildImagesState: LoadState = .idle

    private(set) var serverTypes: [ServerType] = []
    private(set) var serverTypesState: LoadState = .idle
    /// Fetched by both `loadPricing()` (a lightweight `/pricing`-only load,
    /// fired alongside `load()`/`loadMetrics()` in the initial `.task` so
    /// the Control tab's Price row has data as soon as possible) and
    /// `loadServerTypesAndPricing()` (the heavier load scoped to the
    /// Rescale sheet, which also needs the full server-type catalog) —
    /// whichever finishes last wins, which is fine since both fetch the
    /// same `/pricing` endpoint.
    private(set) var pricing: Pricing?

    /// This server's list monthly price at its own location, matched the
    /// same way `CostItemBuilder.matchingPrice` does in the Pricing module
    /// (that helper is `internal` there, so this re-implements the same
    /// three-step lookup: `serverType.id` → its price list → the server's
    /// own location, falling back to the first listed price when the exact
    /// location isn't present). `nil` until both `server` and `pricing`
    /// have loaded, or if pricing genuinely has no entry for this type.
    var listPriceMonthly: Decimal? {
        guard let server, let pricing else { return nil }
        let prices = pricing.serverTypes.first { $0.id == server.serverType.id }?.prices
            ?? server.serverType.prices
        guard !prices.isEmpty else { return nil }
        let match = prices.first { $0.location == server.datacenter.location.name } ?? prices.first
        return match?.monthly.netDecimal
    }

    // MARK: - Rename / labels (not Action-tracked — plain PUT requests)

    private(set) var isRenaming = false
    private(set) var renameError: String?
    private(set) var isSavingLabels = false
    private(set) var labelsError: String?

    private(set) var metrics: ServerMetrics?
    private(set) var metricsState: LoadState = .idle
    var selectedRange: MetricsRange = .oneHour {
        didSet {
            guard oldValue != selectedRange else { return }
            let range = selectedRange
            Task { [weak self] in await self?.loadMetrics(range: range) }
        }
    }

    private let container: AppContainer
    // nonisolated(unsafe): written only from @MainActor methods; deinit (nonisolated)
    // may only cancel, which Task supports from any context.
    @ObservationIgnored
    private nonisolated(unsafe) var actionTask: Task<Void, Never>?
    // nonisolated(unsafe): same rationale as `actionTask` above.
    @ObservationIgnored
    private nonisolated(unsafe) var managementTask: Task<Void, Never>?

    init(route: ServerRoute, container: AppContainer) {
        self.route = route
        self.container = container
    }

    deinit {
        actionTask?.cancel()
        managementTask?.cancel()
    }

    private var client: CloudClient? {
        container.cloudClient(for: route.projectID)
    }

    // MARK: - Loading

    func load() async {
        guard let client else {
            loadState = .failed("No stored credentials for this project.")
            return
        }
        if server == nil { loadState = .loading }
        do {
            let loaded = try await client.server(id: route.serverID)
            server = loaded
            loadState = .loaded
        } catch {
            loadState = .failed(Self.message(for: error))
        }
    }

    func loadMetrics(range: MetricsRange? = nil) async {
        guard let client else { return }
        let range = range ?? selectedRange
        metricsState = .loading
        let end = Date()
        let start = end.addingTimeInterval(-range.duration)
        do {
            let result = try await client.serverMetrics(
                serverID: route.serverID,
                types: [.cpu, .disk, .network],
                start: start,
                end: end,
                step: range.step
            )
            metrics = result
            metricsState = .loaded
        } catch {
            metrics = nil
            metricsState = .failed(Self.message(for: error))
        }
    }

    /// Fetches `/pricing` alone (no server-type catalog) for the Control
    /// tab's Price row — a lighter load than `loadServerTypesAndPricing()`,
    /// which is scoped to the Rescale sheet and additionally lists every
    /// server type. Errors are swallowed: pricing isn't primary content, so
    /// a failed fetch just leaves the Price row showing an override (if
    /// any) or "Price unavailable" rather than surfacing a banner for a
    /// non-critical background load.
    ///
    /// No cross-screen cache: this view model is recreated per visit to
    /// Server Detail (see `ServerDetailView`'s `.task`), so there's nowhere
    /// durable to keep a hit within `Hetzly/Features/Servers/`'s scope — a
    /// shared `ResponseCache` instance would need to live on `AppContainer`,
    /// which this wave doesn't touch.
    func loadPricing() async {
        guard let client else { return }
        pricing = try? await client.pricing()
    }

    // MARK: - Actions

    func clearActionError() {
        actionError = nil
        actionErrorIsPermissionError = false
    }

    func acknowledgeSuccess() {
        lastActionSucceeded = false
    }

    func runAction(_ kind: PowerAction) {
        guard let client, activeAction == nil else { return }
        actionError = nil
        actionErrorIsPermissionError = false
        lastActionSucceeded = false
        actionTask?.cancel()
        actionTask = Task { [weak self] in
            await self?.track(kind, using: client)
        }
    }

    private func track(_ kind: PowerAction, using client: CloudClient) async {
        activeAction = ActiveAction(kind: kind, progress: 0)
        // Registers this action with `NotificationService` before the
        // request even fires: if the app backgrounds partway through, its
        // `beginBackgroundTask` reservation is already open, and whichever
        // terminal branch below runs calls `finish(_:success:)` exactly
        // once to post a "backgrounded only" local notification (a
        // foreground completion is already covered by the in-app success
        // toast/haptic `lastActionSucceeded` drives).
        let notification = container.notificationService.notifyOnCompletion(
            actionTitle: kind.title, serverName: server?.name ?? "Server #\(route.serverID)"
        )
        do {
            let action = try await perform(kind, on: client)
            activeAction = ActiveAction(kind: kind, progress: action.progress)
            let tracker = ActionTracker(client: client)
            for await update in await tracker.track(actionID: action.id) {
                switch update {
                case .progress(let running):
                    activeAction = ActiveAction(kind: kind, progress: running.progress)
                case .finished:
                    activeAction = nil
                    lastActionSucceeded = true
                    lastSucceededAction = kind
                    container.notificationService.finish(notification, success: true)
                    if kind == .delete {
                        didDeleteServer = true
                    } else {
                        await load()
                    }
                case .failed(let underlying):
                    // Contract types `.failed`'s payload as "HetznerAPIError
                    // or action error" — treated generically as `Error` here
                    // so this keeps working regardless of which concrete
                    // type ActionTracker settles on.
                    activeAction = nil
                    actionError = Self.message(for: underlying)
                    // `underlying` is statically `HetznerAPIError` (see the
                    // comment above), so no conditional cast is needed here
                    // unlike the generic `Error` catch clauses below.
                    actionErrorIsPermissionError = underlying.isPermissionError
                    container.notificationService.finish(notification, success: false)
                case .timedOut:
                    activeAction = nil
                    actionError = "This is taking longer than expected. Check back shortly."
                    actionErrorIsPermissionError = false
                    // Treated as a failure for notification purposes too —
                    // there's no further terminal update to wait for, and
                    // "taking longer than expected" is the same bucket the
                    // inline error card already shows.
                    container.notificationService.finish(notification, success: false)
                }
            }
        } catch {
            activeAction = nil
            actionError = Self.message(for: error)
            actionErrorIsPermissionError = (error as? HetznerAPIError)?.isPermissionError ?? false
            container.notificationService.finish(notification, success: false)
        }
    }

    private func perform(_ kind: PowerAction, on client: CloudClient) async throws -> Action {
        switch kind {
        case .powerOn: try await client.powerOn(serverID: route.serverID)
        case .shutdown: try await client.shutdown(serverID: route.serverID)
        case .reboot: try await client.reboot(serverID: route.serverID)
        case .reset: try await client.reset(serverID: route.serverID)
        case .powerOff: try await client.powerOff(serverID: route.serverID)
        case .delete: try await client.deleteServer(id: route.serverID)
        }
    }

    // MARK: - Management actions

    func clearManagementActionError() {
        managementActionError = nil
        managementActionErrorIsPermissionError = false
    }

    func acknowledgeManagementSuccess() {
        lastManagementActionSucceeded = false
    }

    func dismissRevealedSecret() {
        revealedSecret = nil
    }

    func dismissConsoleCredentials() {
        consoleCredentials = nil
    }

    /// Fires any of the single-step `ServerManagementAction` cases. Guarded
    /// by both `activeAction` and `managementActiveAction` so a management
    /// action never overlaps a power action (or another management action,
    /// or an in-flight `runRescale` chain) on the same server.
    func runManagementAction(_ kind: ServerManagementAction) {
        guard let client, managementActiveAction == nil, activeAction == nil else { return }
        managementActionError = nil
        managementActionErrorIsPermissionError = false
        lastManagementActionSucceeded = false
        managementTask?.cancel()
        managementTask = Task { [weak self] in
            await self?.trackManagement(kind, using: client)
        }
    }

    private func trackManagement(_ kind: ServerManagementAction, using client: CloudClient) async {
        managementActiveAction = ManagementActiveAction(stepLabel: kind.progressVerb, progress: 0)
        let notification = container.notificationService.notifyOnCompletion(
            actionTitle: kind.title, serverName: server?.name ?? "Server #\(route.serverID)"
        )
        do {
            let action = try await performManagement(kind, on: client)
            managementActiveAction = ManagementActiveAction(stepLabel: kind.progressVerb, progress: action.progress)
            try await trackToCompletion(action, using: client) { [weak self] progress in
                self?.managementActiveAction = ManagementActiveAction(stepLabel: kind.progressVerb, progress: progress)
            }
            managementActiveAction = nil
            lastManagementActionSucceeded = true
            lastManagementSuccessText = kind.successText
            container.notificationService.finish(notification, success: true)
            switch kind {
            case .attachISO(let iso): locallyAttachedISO = iso
            case .detachISO: locallyAttachedISO = nil
            case .createSnapshot: await loadSnapshots()
            default: break
            }
            await load()
        } catch {
            managementActiveAction = nil
            managementActionError = Self.message(for: error)
            managementActionErrorIsPermissionError = (error as? HetznerAPIError)?.isPermissionError ?? false
            container.notificationService.finish(notification, success: false)
        }
    }

    /// Fires the wire request for `kind` and returns the `Action` to track.
    /// Also stashes any secret/credential payload the response carries
    /// (`revealedSecret`/`consoleCredentials`) immediately — those are valid
    /// as soon as the response arrives, independent of whether the
    /// associated `Action` later finishes, fails, or times out.
    private func performManagement(_ kind: ServerManagementAction, on client: CloudClient) async throws -> Action {
        switch kind {
        case .createSnapshot(let description):
            let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = try await client.createImage(
                serverID: route.serverID,
                description: trimmed.isEmpty ? nil : trimmed,
                type: .snapshot
            )
            return result.action
        case .enableBackups:
            return try await client.enableBackups(serverID: route.serverID)
        case .disableBackups:
            return try await client.disableBackups(serverID: route.serverID)
        case .enableRescue(let sshKeyIDs):
            let result = try await client.enableRescue(serverID: route.serverID, sshKeyIDs: sshKeyIDs)
            if !result.rootPassword.isEmpty {
                // This is a rescue-SYSTEM password (only valid once the
                // server actually boots into rescue), not the normal-OS root
                // password — still worth saving durably so the Credentials
                // section on this screen stays current, same as the
                // reset-root-password case below.
                try? ServerCredentialsVault.saveRootPassword(result.rootPassword, serverID: route.serverID)
                revealedSecret = RevealedSecret(
                    title: "Rescue Root Password",
                    secret: result.rootPassword,
                    note: "Shown once and saved on this device. Reboot the server to actually enter rescue mode — Hetzner only boots into rescue on the next restart.",
                    offersReboot: true
                )
            }
            return result.action
        case .disableRescue:
            return try await client.disableRescue(serverID: route.serverID)
        case .rebuild(let image):
            return try await client.rebuild(serverID: route.serverID, imageIDOrName: String(image.id))
        case .attachISO(let iso):
            return try await client.attachISO(serverID: route.serverID, iso: String(iso.id))
        case .detachISO:
            return try await client.detachISO(serverID: route.serverID)
        case .changeProtection(let delete, let rebuild):
            return try await client.changeProtection(serverID: route.serverID, delete: delete, rebuild: rebuild)
        case .resetRootPassword:
            let result = try await client.resetPassword(serverID: route.serverID)
            if !result.rootPassword.isEmpty {
                try? ServerCredentialsVault.saveRootPassword(result.rootPassword, serverID: route.serverID)
                revealedSecret = RevealedSecret(
                    title: "New Root Password",
                    secret: result.rootPassword,
                    note: "Shown once and saved on this device. Only takes effect immediately with the qemu guest agent installed and the disk mounted normally — otherwise it applies on next boot."
                )
            }
            return result.action
        case .requestConsole:
            let result = try await client.requestConsole(serverID: route.serverID)
            consoleCredentials = ConsoleCredentials(wssURL: result.wssURL, password: result.password)
            return result.action
        }
    }

    // MARK: - Rescale (multi-step chained flow)

    /// Resizes the server to `serverType`. Hetzner requires the server to be
    /// off before `change_type`, so when it's currently running this chains
    /// shutdown → poll-until-off → resize → (optionally) power back on,
    /// surfacing each step through `managementActiveAction` so the active-
    /// action card reads "Shutting Down… / Resizing… / Powering On…" in
    /// sequence rather than one opaque "Rescaling…" step.
    func runRescale(serverType: ServerType, upgradeDisk: Bool, powerOnAfter: Bool) {
        guard let client, managementActiveAction == nil, activeAction == nil else { return }
        managementActionError = nil
        managementActionErrorIsPermissionError = false
        lastManagementActionSucceeded = false
        managementTask?.cancel()
        managementTask = Task { [weak self] in
            await self?.trackRescale(
                serverType: serverType, upgradeDisk: upgradeDisk, powerOnAfter: powerOnAfter, using: client
            )
        }
    }

    private func trackRescale(
        serverType: ServerType, upgradeDisk: Bool, powerOnAfter: Bool, using client: CloudClient
    ) async {
        // One notification for the whole chained flow (shutdown → resize →
        // optional power-on), not one per step — matches how
        // `lastManagementSuccessText` only fires once, at the very end.
        let notification = container.notificationService.notifyOnCompletion(
            actionTitle: "Resize", serverName: server?.name ?? "Server #\(route.serverID)"
        )
        do {
            let serverID = route.serverID
            let wasRunning = server?.status == .running
            if wasRunning {
                try await runRescaleStep("Shutting Down", using: client) {
                    try await client.shutdown(serverID: serverID)
                }
                try await pollUntilOff(using: client)
            }

            try await runRescaleStep("Resizing", using: client) {
                try await client.changeType(
                    serverID: serverID, serverTypeID: serverType.id, upgradeDisk: upgradeDisk
                )
            }

            if powerOnAfter {
                try await runRescaleStep("Powering On", using: client) {
                    try await client.powerOn(serverID: serverID)
                }
            }

            managementActiveAction = nil
            lastManagementActionSucceeded = true
            lastManagementSuccessText = "Resized to \(serverType.name)."
            container.notificationService.finish(notification, success: true)
            await load()
        } catch {
            managementActiveAction = nil
            managementActionError = Self.message(for: error)
            managementActionErrorIsPermissionError = (error as? HetznerAPIError)?.isPermissionError ?? false
            container.notificationService.finish(notification, success: false)
        }
    }

    private func runRescaleStep(
        _ label: String, using client: CloudClient, start: () async throws -> Action
    ) async throws {
        managementActiveAction = ManagementActiveAction(stepLabel: label, progress: 0)
        let started = try await start()
        managementActiveAction = ManagementActiveAction(stepLabel: label, progress: started.progress)
        try await trackToCompletion(started, using: client) { [weak self] progress in
            self?.managementActiveAction = ManagementActiveAction(stepLabel: label, progress: progress)
        }
    }

    /// Polls `server(id:)` directly (not `ActionTracker`, which tracks
    /// `Action`s, not server state) until the server reports `.off` or 60
    /// attempts (~2 minutes at the 2s interval below) pass.
    private func pollUntilOff(using client: CloudClient) async throws {
        for _ in 0..<60 {
            let current = try await client.server(id: route.serverID)
            server = current
            if current.status == .off { return }
            try await Task.sleep(for: .seconds(2))
        }
        throw ManagementFlowError.timedOut
    }

    /// Shared `ActionTracker` consumption loop for both `trackManagement`
    /// and `runRescaleStep`: awaits an already-started `Action` to
    /// completion, forwarding progress via `onProgress`, and throws on
    /// failure/timeout instead of yielding a terminal state — callers
    /// handle both with one `catch` at the top of their flow.
    private func trackToCompletion(
        _ action: Action, using client: CloudClient, onProgress: @escaping (Int) -> Void
    ) async throws {
        if action.status == .success { return }
        let tracker = ActionTracker(client: client)
        for await update in await tracker.track(actionID: action.id) {
            switch update {
            case .progress(let running):
                onProgress(running.progress)
            case .finished:
                return
            case .failed(let underlying):
                throw underlying
            case .timedOut:
                throw ManagementFlowError.timedOut
            }
        }
    }

    // MARK: - Catalog data for management sheets

    func loadSnapshots() async {
        guard let client else { return }
        snapshotsState = .loading
        do {
            let all = try await client.listImages(type: .snapshot)
            snapshots = all.filter { $0.createdFrom?.id == route.serverID }
            snapshotsState = .loaded
        } catch {
            snapshotsState = .failed(Self.message(for: error))
        }
    }

    func deleteSnapshot(_ image: Image) async {
        guard let client else { return }
        do {
            try await client.deleteImage(id: image.id)
            snapshots.removeAll { $0.id == image.id }
        } catch {
            snapshotsState = .failed(Self.message(for: error))
        }
    }

    func loadSSHKeys() async {
        guard let client else { return }
        sshKeysState = .loading
        do {
            sshKeys = try await client.listSSHKeys()
            sshKeysState = .loaded
        } catch {
            sshKeysState = .failed(Self.message(for: error))
        }
    }

    func loadISOs() async {
        guard let client else { return }
        isosState = .loading
        do {
            isos = try await client.listISOs()
            isosState = .loaded
        } catch {
            isosState = .failed(Self.message(for: error))
        }
    }

    /// Loads system images plus this server's own snapshots — the two
    /// sources `RebuildSheet` groups by flavor for rebuild-from-image.
    func loadRebuildImages() async {
        guard let client else { return }
        rebuildImagesState = .loading
        do {
            async let systemImages = client.listImages(type: .system)
            async let ownSnapshots = client.listImages(type: .snapshot)
            let (system, snapshotsResult) = try await (systemImages, ownSnapshots)
            rebuildImages = system + snapshotsResult.filter { $0.createdFrom?.id == route.serverID }
            rebuildImagesState = .loaded
        } catch {
            rebuildImagesState = .failed(Self.message(for: error))
        }
    }

    func loadServerTypesAndPricing() async {
        guard let client else { return }
        serverTypesState = .loading
        do {
            async let types = client.listServerTypes()
            async let priceList = client.pricing()
            let (loadedTypes, loadedPricing) = try await (types, priceList)
            serverTypes = loadedTypes
            pricing = loadedPricing
            serverTypesState = .loaded
        } catch {
            serverTypesState = .failed(Self.message(for: error))
        }
    }

    // MARK: - Rename / labels

    /// Validates and applies a new hostname via `PUT /servers/{id}`. Not
    /// Action-tracked — `CloudClient.rename` returns the updated `Server`
    /// directly, synchronously. Returns `true` on success so the caller
    /// (an `.alert` TextField flow) knows whether to dismiss.
    @discardableResult
    func rename(to newName: String) async -> Bool {
        guard let client else { return false }
        isRenaming = true
        renameError = nil
        defer { isRenaming = false }
        do {
            server = try await client.rename(serverID: route.serverID, name: newName)
            return true
        } catch {
            renameError = Self.message(for: error)
            return false
        }
    }

    @discardableResult
    func updateLabels(_ labels: [String: String]) async -> Bool {
        guard let client else { return false }
        isSavingLabels = true
        labelsError = nil
        defer { isSavingLabels = false }
        do {
            server = try await client.updateLabels(serverID: route.serverID, labels: labels)
            return true
        } catch {
            labelsError = Self.message(for: error)
            return false
        }
    }

    /// Local stand-in for `ActionUpdate.timedOut`/generic-Error cases inside
    /// this file's own multi-step flows (`pollUntilOff`, `trackToCompletion`)
    /// — mapped to the same "taking longer than expected" copy as the power
    /// row's timeout in `Self.message(for:)`.
    private enum ManagementFlowError: Error {
        case timedOut
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? HetznerAPIError {
            return apiError.userMessage
        }
        if error is ManagementFlowError {
            return "This is taking longer than expected. Check back shortly."
        }
        return "Something went wrong. Please try again."
    }
}
