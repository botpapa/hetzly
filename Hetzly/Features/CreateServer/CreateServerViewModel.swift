import Foundation
import HetznerKit
import Observation

/// `HetznerKit.Image` shares a bare name with `SwiftUI.Image` — every file in
/// this feature spells the model type through this alias instead of
/// qualifying `HetznerKit.Image` at every call site.
typealias HetznerImage = HetznerKit.Image

/// The four steps of the create-server wizard, in order.
enum CreateServerStep: Int, CaseIterable, Identifiable, Sendable {
    case location, image, type, config

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .location: "Location"
        case .image: "Image"
        case .type: "Type"
        case .config: "Configure"
        }
    }
}

/// Drives `CreateServerFlow`: loads the catalog needed to configure a new
/// server (locations, system images, server types, SSH keys, networks,
/// firewalls, pricing), holds the in-progress selections, computes the live
/// price preview, and — once the user confirms — assembles the
/// `CreateServerRequest` and tracks the resulting action to completion.
///
/// Deliberately does not store an `AppContainer`/`CloudClient` reference:
/// `loadCatalog(container:)` and `createServer(container:)` both take the
/// container as a parameter, so preview/test code can seed a fully-populated
/// instance (see `CreateServerPreviewFixtures`) without touching the network
/// or constructing a real container.
@MainActor
@Observable
final class CreateServerViewModel {
    enum CatalogLoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// Mirrors `CreateServerViewModel`'s binding contract: `configuring` while
    /// the wizard is on screen, `creating` while `POST /servers` + its action
    /// are in flight, `succeeded`/`failed` once that resolves. `Server` and
    /// the phase's other payloads are all `Equatable`, so the phase itself is
    /// too — useful for `.onChange`/animation triggers in the view layer.
    enum Phase: Equatable {
        case configuring
        case creating(progress: Int)
        case succeeded(Server)
        case failed(String)

        var isCreating: Bool {
            if case .creating = self { return true }
            return false
        }
    }

    /// Net hourly/monthly price for the current location + server type
    /// selection, backups surcharge already folded in when enabled.
    struct PricePreview: Equatable {
        let hourlyNet: Decimal
        let monthlyNet: Decimal
        let currency: String
    }

    enum CPUFilter: String, CaseIterable, Identifiable, Sendable {
        case all, shared, dedicated

        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "All"
            case .shared: "Shared"
            case .dedicated: "Dedicated"
            }
        }
        var cpuType: CPUType? {
            switch self {
            case .all: nil
            case .shared: .shared
            case .dedicated: .dedicated
            }
        }
    }

    let projectID: UUID

    // MARK: - Wizard position

    var step: CreateServerStep = .location

    // MARK: - Catalog

    private(set) var catalogState: CatalogLoadState = .idle
    private(set) var locations: [Location] = []
    private(set) var images: [HetznerImage] = []
    private(set) var serverTypes: [ServerType] = []
    private(set) var sshKeys: [SSHKey] = []
    private(set) var networks: [Network] = []
    private(set) var firewalls: [Firewall] = []
    private(set) var pricing: Pricing?

    // MARK: - Selections

    var selectedLocation: Location? {
        didSet {
            guard selectedLocation?.id != oldValue?.id else { return }
            if let location = selectedLocation, let type = selectedServerType,
               monthlyPrice(for: type, at: location) == nil {
                selectedServerType = nil
            }
        }
    }

    var selectedImage: HetznerImage? {
        didSet {
            guard selectedImage?.id != oldValue?.id else { return }
            if let architecture = selectedImage?.architecture, architecture != .unknown {
                typeArchitectureFilter = architecture
            }
        }
    }

    var selectedServerType: ServerType?

    var name: String = ""
    var sshKeyIDs: Set<Int> = []
    var networkIDs: Set<Int> = []
    var firewallIDs: Set<Int> = []
    var backupsEnabled = false
    var userData: String = ""
    var ipv4Enabled = true
    var ipv6Enabled = true

    /// Step 3 filter state — UI-only, not part of the create request.
    var typeArchitectureFilter: Architecture = .x86
    var typeCPUFilter: CPUFilter = .all

    // MARK: - Result

    private(set) var phase: Phase = .configuring
    /// Set from `CreateServerResult.rootPassword` when the request completes
    /// with no SSH keys attached. A secret — never logged, only ever shown
    /// once and copied via `SensitivePasteboard`. Also durably saved to
    /// `ServerCredentialsVault` the moment it arrives — see `createServer`
    /// — so `pendingSecret(forServerID:)` below can recover it even after
    /// this view model (and the in-memory copy here) no longer exist.
    private(set) var createdRootPassword: String?

    init(
        projectID: UUID,
        step: CreateServerStep = .location,
        catalogState: CatalogLoadState = .idle,
        locations: [Location] = [],
        images: [HetznerImage] = [],
        serverTypes: [ServerType] = [],
        sshKeys: [SSHKey] = [],
        networks: [Network] = [],
        firewalls: [Firewall] = [],
        pricing: Pricing? = nil,
        selectedLocation: Location? = nil,
        selectedImage: HetznerImage? = nil,
        selectedServerType: ServerType? = nil,
        name: String = "",
        backupsEnabled: Bool = false,
        phase: Phase = .configuring,
        createdRootPassword: String? = nil
    ) {
        self.projectID = projectID
        self.step = step
        self.catalogState = catalogState
        self.locations = locations
        self.images = images
        self.serverTypes = serverTypes
        self.sshKeys = sshKeys
        self.networks = networks
        self.firewalls = firewalls
        self.pricing = pricing
        self.selectedLocation = selectedLocation
        self.selectedImage = selectedImage
        self.selectedServerType = selectedServerType
        self.name = name.isEmpty ? NameGenerator.suggest() : name
        self.backupsEnabled = backupsEnabled
        self.phase = phase
        self.createdRootPassword = createdRootPassword
        if let architecture = selectedImage?.architecture, architecture != .unknown {
            self.typeArchitectureFilter = architecture
        }
    }

    // MARK: - Catalog loading

    func loadCatalog(container: AppContainer) async {
        guard let client = container.cloudClient(for: projectID) else {
            catalogState = .failed("No stored credentials for this project.")
            return
        }
        catalogState = .loading
        do {
            async let locationsTask = client.listLocations()
            async let imagesTask = client.listImages(type: .system)
            async let serverTypesTask = client.listServerTypes()
            async let sshKeysTask = client.listSSHKeys()
            async let networksTask = client.listNetworks()
            async let firewallsTask = client.listFirewalls()
            async let pricingTask = client.pricing()

            let (
                loadedLocations, loadedImages, loadedServerTypes,
                loadedSSHKeys, loadedNetworks, loadedFirewalls, loadedPricing
            ) = try await (
                locationsTask, imagesTask, serverTypesTask,
                sshKeysTask, networksTask, firewallsTask, pricingTask
            )

            locations = loadedLocations.sorted { $0.city.localizedCaseInsensitiveCompare($1.city) == .orderedAscending }
            images = loadedImages
            serverTypes = loadedServerTypes
            sshKeys = loadedSSHKeys
            networks = loadedNetworks
            firewalls = loadedFirewalls
            pricing = loadedPricing
            catalogState = .loaded
        } catch {
            catalogState = .failed(Self.message(for: error))
        }
    }

    /// Re-fetches SSH keys after the wizard's in-flow "Add SSH Key" sheet
    /// (step 4) creates one. Diffs against the keys already loaded to find
    /// the newly created key and auto-selects it, so the user doesn't have
    /// to hunt for the row they just added. Silently no-ops on failure —
    /// the sheet itself already reported success, and a failed refresh just
    /// means the new key stays unselected until the wizard's own retry/back
    /// navigation reloads the catalog.
    func refreshSSHKeys(container: AppContainer) async {
        guard let client = container.cloudClient(for: projectID) else { return }
        let previousIDs = Set(sshKeys.map(\.id))
        guard let refreshed = try? await client.listSSHKeys() else { return }
        sshKeys = refreshed
        if let newKey = refreshed.first(where: { !previousIDs.contains($0.id) }) {
            sshKeyIDs.insert(newKey.id)
        }
    }

    // MARK: - Step navigation

    var canContinue: Bool {
        switch step {
        case .location: selectedLocation != nil
        case .image: selectedImage != nil
        case .type: selectedServerType != nil
        case .config: isNameValid
        }
    }

    func advance() {
        guard let next = CreateServerStep(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func goBack() {
        guard let previous = CreateServerStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    // MARK: - Server type filtering (step 3)

    /// Server types available for the current architecture/CPU filter at the
    /// selected location, cheapest first. A type is hidden entirely when it
    /// has no price entry at the location (Hetzner doesn't sell every type in
    /// every region) and deprecated types are hidden unless already selected.
    var filteredServerTypes: [ServerType] {
        guard let location = selectedLocation else { return [] }
        return serverTypes
            .filter { type in
                guard type.architecture == typeArchitectureFilter else { return false }
                if let requiredCPUType = typeCPUFilter.cpuType, type.cpuType != requiredCPUType { return false }
                guard monthlyPrice(for: type, at: location) != nil else { return false }
                if type.deprecated == true, selectedServerType?.id != type.id { return false }
                return true
            }
            .sorted { (monthlyPrice(for: $0, at: location) ?? 0) < (monthlyPrice(for: $1, at: location) ?? 0) }
    }

    func monthlyPrice(for type: ServerType, at location: Location) -> Decimal? {
        guard let priced = pricing?.serverTypes.first(where: { $0.id == type.id }) else { return nil }
        guard let entry = priced.prices.first(where: { $0.location == location.name }) else { return nil }
        return entry.monthly.netDecimal
    }

    // MARK: - Pricing preview

    var currencyCode: String { pricing?.currency ?? "EUR" }

    /// Fraction (e.g. `0.2` for 20%) backups add on top of the base price.
    /// Falls back to Hetzner's documented 20% if `/pricing` didn't include a
    /// parseable percentage.
    private var backupSurchargeFraction: Decimal {
        guard let raw = pricing?.serverBackupPercentage, let value = Decimal(string: raw) else { return 0.2 }
        return value / 100
    }

    var pricePreview: PricePreview? {
        guard let type = selectedServerType, let location = selectedLocation else { return nil }
        guard let priced = pricing?.serverTypes.first(where: { $0.id == type.id }) else { return nil }
        guard let entry = priced.prices.first(where: { $0.location == location.name }) else { return nil }
        guard let hourly = entry.hourly.netDecimal, let monthly = entry.monthly.netDecimal else { return nil }
        let multiplier: Decimal = backupsEnabled ? (1 + backupSurchargeFraction) : 1
        return PricePreview(hourlyNet: hourly * multiplier, monthlyNet: monthly * multiplier, currency: currencyCode)
    }

    /// The extra €/mo backups add, shown next to the backups toggle. `nil`
    /// until a location + type are both chosen.
    var backupsMonthlyDelta: Decimal? {
        guard let type = selectedServerType, let location = selectedLocation,
              let monthly = monthlyPrice(for: type, at: location) else { return nil }
        return monthly * backupSurchargeFraction
    }

    // MARK: - Name

    var isNameValid: Bool { Self.isValidServerName(name) }

    func regenerateName() {
        name = NameGenerator.suggest()
    }

    /// Loosely RFC1123-label-shaped: 1–63 characters, letters/digits/hyphen/
    /// dot only, and it can't start or end on a hyphen or dot.
    static func isValidServerName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 63 else { return false }
        guard let first = name.first, let last = name.last else { return false }
        guard first != "-", first != ".", last != "-", last != "." else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.")
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    // MARK: - Create

    func createServer(container: AppContainer) async {
        guard let client = container.cloudClient(for: projectID) else {
            phase = .failed("No stored credentials for this project.")
            return
        }
        guard let location = selectedLocation, let image = selectedImage, let serverType = selectedServerType else {
            phase = .failed("Please complete every step before creating the server.")
            return
        }

        phase = .creating(progress: 0)

        let trimmedUserData = userData.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = CreateServerRequest(
            name: name,
            serverType: serverType.name,
            image: image.name ?? String(image.id),
            location: location.name,
            sshKeys: sshKeyIDs.map(String.init),
            networks: Array(networkIDs),
            firewalls: firewallIDs.map { CreateServerRequest.FirewallReference(firewall: $0) },
            userData: trimmedUserData.isEmpty ? nil : trimmedUserData,
            backups: backupsEnabled,
            publicNet: CreateServerRequest.PublicNetSelection(enableIPv4: ipv4Enabled, enableIPv6: ipv6Enabled)
        )

        do {
            let result = try await client.createServer(request)
            createdRootPassword = result.rootPassword
            // Persist immediately, not just on-screen: `createdRootPassword`
            // only lives in memory for as long as this view model does, so
            // if the app is killed while the result screen is still up
            // (background jetsam, crash, force-quit) the in-memory copy is
            // gone — and Hetzner never shows this password again, so the
            // only recovery would be a rescue-mode password reset. Saving to
            // `ServerCredentialsVault` the instant it arrives closes that
            // window; it's a durable save (not cleared on "Done"), so the
            // user can also come back for it later via the create flow's
            // "saved on this device" banner.
            if let password = result.rootPassword {
                try? ServerCredentialsVault.saveRootPassword(password, serverID: result.server.id)
            }
            let tracker = ActionTracker(client: client)
            for await update in await tracker.track(actionID: result.action.id) {
                switch update {
                case .progress(let action):
                    phase = .creating(progress: action.progress)
                case .finished:
                    phase = .succeeded(result.server)
                case .failed(let underlying):
                    phase = .failed(Self.message(for: underlying))
                case .timedOut:
                    // The server itself was created synchronously by the
                    // initial request — only the provisioning action's
                    // completion is what timed out — so this still counts as
                    // success from the user's point of view.
                    phase = .succeeded(result.server)
                }
            }
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    /// Resets back to the config step with every selection intact, for the
    /// failure phase's "Try Again".
    func retryFromFailure() {
        phase = .configuring
    }

    /// The one blessed access point this feature uses to read back a
    /// durably-saved root password (e.g. for `CreateServerFlow`'s "saved on
    /// this device" banner) rather than reaching into `ServerCredentialsVault`
    /// directly — so a future storage-format change only needs updating
    /// here. A thin passthrough today; kept as its own method because other
    /// wizard steps may eventually want their own read path without knowing
    /// the vault's storage details.
    static func pendingSecret(forServerID serverID: Int) -> String? {
        ServerCredentialsVault.rootPassword(serverID: serverID)
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? HetznerAPIError {
            return apiError.userMessage
        }
        return "Something went wrong. Please try again."
    }
}
