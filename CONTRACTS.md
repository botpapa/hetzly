# Hetzly — Module Contracts & Conventions

This document is the coordination contract between parallel workers. Every worker
owns a disjoint set of paths and MUST NOT create or edit files outside them.
Where modules touch, the public API defined here is binding.

## Global conventions (all workers)

- Swift 6 language mode, strict concurrency. No `@unchecked Sendable` unless justified in a comment.
- iOS 26.0 minimum deployment target. Use real iOS 26 Liquid Glass APIs (`.glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)` / `.glassProminent`) — no fake blurs.
- Zero third-party dependencies. Apple frameworks + stdlib only.
- No force unwraps (`!`), no `try!`, no `fatalError` in app-target code (allowed in tests).
- No `print`/`os_log` of tokens, Authorization headers, or credential-bearing bodies.
- Every SwiftUI view file ends with a `#Preview` using dark mode: `.preferredColorScheme(.dark)`.
- File header comment: none (no boilerplate headers). MIT license lives in LICENSE only.
- Naming: types `UpperCamelCase`, one primary type per file, file named after it.

## Targets

- **HetznerKit** — SPM package at `Packages/HetznerKit`. UI-free. Platforms: iOS 26, macOS 26 (macOS so `swift test` runs on CI/dev Macs). `Package.swift` is already written — do not modify without instruction.
- **Hetzly** — app target, sources globbed from `Hetzly/` by xcodegen (`project.yml`). Depends on local package HetznerKit. Bundle ID `com.hetzly.app`, display name "Hetzly".

## Binding public APIs (cross-module touchpoints)

### HetznerKit Core (`Packages/HetznerKit/Sources/HetznerKit/Core/`)

```swift
public enum AuthMethod: Sendable {
    case bearer(token: String)
    case basic(username: String, password: String)
}

public struct APIConfiguration: Sendable {
    public let baseURL: URL
    public let auth: AuthMethod
    public init(baseURL: URL, auth: AuthMethod)
}

/// Abstraction over URLSession so tests inject a mock transport.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct Endpoint: Sendable {
    public var method: HTTPMethod            // GET/POST/PUT/DELETE enum
    public var path: String                  // e.g. "/servers"
    public var query: [URLQueryItem]
    public var body: Data?
    public init(method: HTTPMethod = .get, path: String, query: [URLQueryItem] = [], body: Data? = nil)
}

public enum HetznerAPIError: Error, Sendable {
    case unauthorized                        // 401
    case forbidden(message: String?)         // 403
    case notFound
    case rateLimited(retryAfter: TimeInterval?)
    case api(code: String, message: String)  // Hetzner error envelope
    case http(status: Int)
    case decoding(underlying: String)
    case transport(underlying: String)
    public var userMessage: String { get }   // human sentence, never raw JSON
}

public actor HetznerHTTPClient {
    public init(configuration: APIConfiguration, transport: HTTPTransport, rateLimiter: RateLimiter)
    public func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T
    public func sendExpectingNoContent(_ endpoint: Endpoint) async throws
}

public actor RateLimiter {
    public init(budget: Int, window: TimeInterval)   // conservative defaults per API
    public func waitForSlot() async
    public func record(response: HTTPURLResponse)    // reads RateLimit-* headers; 429 → back off to RateLimit-Reset
}

/// Transparent pagination over Hetzner `meta.pagination`.
public func paginated<T: Decodable & Sendable>(
    client: HetznerHTTPClient, endpoint: Endpoint, itemsKey: String, perPage: Int
) -> AsyncThrowingStream<[T], Error>

public actor ResponseCache {
    public init()
    public func value<T: Sendable>(for key: String, ttl: TimeInterval, as type: T.Type) -> T?
    public func store<T: Sendable>(_ value: T, for key: String)
}
```

### DesignSystem (`Hetzly/DesignSystem/`)

```swift
enum HetzlyColors {  // static Color values
    canvas /*#0A0A0C*/, accent /*#F0483E*/, destructive /*#FF5C5C*/,
    textPrimary /*#F5F5F7*/, textSecondary /*#9A9AA2*/, textTertiary /*#5A5A63*/,
    statusRunning /*#30D158*/, statusOff /*#5A5A63*/, statusTransitioning /*#FFD60A*/, statusError /*#FF453A*/
}
enum Spacing { unit=4, screenMargin=20, cardPadding=16 }
enum Radius  { card=24, control=16 }

struct GlassCard<Content: View>: View          // .glassEffect(.regular, in: .rect(cornerRadius: 24)), interactive variant flag
struct GlassChip: View                          // capsule label chip
struct StatusDot: View                          // status enum → color; pulses only when transitioning; respects Reduce Motion
struct SectionLabel: View                       // uppercase, tracking 1.5, textTertiary
struct CanvasBackground: View                   // near-black + subtle radial depth gradient
extension View { func hetzlyMonoNumbers() -> some View }  // SF Mono + monospacedDigit
```

All glass components MUST provide solid fallbacks when `accessibilityReduceTransparency` is on.

### Security (`Hetzly/Security/`)

```swift
struct KeychainStore: Sendable {
    func save(_ data: Data, service: String, account: String) throws     // ThisDeviceOnly, non-synchronizable
    func read(service: String, account: String) throws -> Data?
    func delete(service: String, account: String) throws                  // verified delete
}
@MainActor final class BiometricGate {
    func authenticate(reason: String) async -> Bool   // biometrics w/ passcode fallback
}
struct PrivacyOverlay: ViewModifier                    // blur overlay on scenePhase != .active
struct SecureTokenField: View                          // secure entry + reveal toggle, no autocorrect/caps
```

### Mascot (`Hetzly/Mascot/`)

```swift
enum MascotState: String, CaseIterable { case idle, walk, run, sleep, alarm, celebrate, work, peek }
struct MascotView: View {
    init(state: MascotState, scale: CGFloat = 2)
    // TimelineView(.animation) + Canvas, nearest-neighbor, static frame when Reduce Motion is on
}
```

Sprite atlases: JSON frame data + 32×32 pixel data generated in Swift (or JSON resources), total budget < 300 KB.

### App shell (`Hetzly/App/`)

```swift
@main struct HetzlyApp: App
@MainActor @Observable final class AppContainer   // DI: builds clients, keychain, stores; injected via .environment
struct RootView: View                             // switches Onboarding vs MainTabView placeholder
```

## Wave 2 contracts (M1: CloudAPI + app features)

Wave 1 code is committed and real — READ the actual source when consuming it
(Core in `Packages/HetznerKit/Sources/HetznerKit/Core/`, DesignSystem/Security/Mascot under `Hetzly/`).
The APIs below are binding for wave-2 cross-worker touchpoints.

### CloudAPI (`Packages/HetznerKit/Sources/HetznerKit/CloudAPI/`) — Worker A

```swift
public actor CloudClient {
    public init(token: String, transport: HTTPTransport = URLSessionTransport())
    public func validateToken() async throws                      // cheap authenticated GET; throws HetznerAPIError.unauthorized on bad token
    public func listServers() async throws -> [Server]           // full pagination, sorted by name
    public func server(id: Int) async throws -> Server
    public func deleteServer(id: Int) async throws -> Action
    public func powerOn(serverID: Int) async throws -> Action
    public func powerOff(serverID: Int) async throws -> Action    // hard power off
    public func shutdown(serverID: Int) async throws -> Action    // ACPI
    public func reboot(serverID: Int) async throws -> Action      // soft
    public func reset(serverID: Int) async throws -> Action       // hard reset
    public func action(id: Int) async throws -> Action
    public func serverMetrics(serverID: Int, types: Set<MetricsType>, start: Date, end: Date, step: TimeInterval) async throws -> ServerMetrics
    public func pricing() async throws -> Pricing                 // callers cache (24h) via ResponseCache
}
public enum MetricsType: String, Sendable { case cpu, disk, network }
```

Models (all `Sendable`, `Codable` with explicit CodingKeys, `Identifiable` where an id exists; unknown enum values decode to `.unknown` — NEVER throw on new server states):
- `Server`: id Int, name, status `ServerStatus` (running, initializing, starting, stopping, off, deleting, migrating, rebuilding, unknown), created Date, publicNet `PublicNet` (ipv4?.ip String, ipv6?.ip String), serverType `ServerType`, datacenter `Datacenter` (location: id/name/city/country/networkZone), labels [String:String], locked Bool, protection (delete Bool, rebuild Bool), backupWindow String?, rescueEnabled Bool, primaryDiskSize Int, includedTraffic Int64?, outgoingTraffic Int64?, ingoingTraffic Int64?
- `ServerType`: id, name, description, cores Int, memory Double (GB), disk Int (GB), cpuType (shared/dedicated/unknown), architecture (x86/arm/unknown), deprecated Bool?, prices: [ServerTypePrice] (location String, hourly PriceValue, monthly PriceValue; PriceValue { net: String, gross: String } + `var netDecimal: Decimal?`)
- `Action`: id, command String, status `ActionStatus` (running/success/error/unknown), progress Int, started Date, finished Date?, error ActionError? (code, message), resources [ActionResource (id, type)]
- `ServerMetrics`: start, end, step, series: [MetricsSeries { name: String, points: [(timestamp: Date, value: Double)] }] — Hetzner returns values as `[[unix_ts, "string-number"]]`; parse defensively
- `Pricing`: currency String, vatRate String, serverTypes/primaryIPs/volumes essentials for cost math

`ActionTracker` (same dir): `public actor ActionTracker { init(client: CloudClient); func track(actionID: Int) -> AsyncStream<ActionUpdate> }` — polls every 2s, exponential backoff after 30s, terminates on success/error/120s timeout. `ActionUpdate` enum: `.progress(Action)`, `.finished(Action)`, `.failed(HetznerAPIError or action error)`, `.timedOut`.

### Pricing engine (`Packages/HetznerKit/Sources/HetznerKit/Pricing/`) — Worker B

Pure, deterministic, fully unit-tested. Own input types (does NOT import CloudAPI models):
```swift
public struct CostItem: Sendable, Identifiable {
    public let id: String; public let name: String; public let kind: CostKind  // server, volume, primaryIP, floatingIP, loadBalancer, backup, dedicated, other
    public let pricing: CostPricing  // .hourly(net: Decimal, monthlyCap: Decimal?), .monthlyFlat(net: Decimal)
    public let createdAt: Date?
    public init(...)
}
public struct CostSummary: Sendable { monthToDate: Decimal, projectedMonthTotal: Decimal, perItem: [ItemCost], currency: String }
public enum CostEngine {
    public static func summary(items: [CostItem], now: Date, calendar: Calendar, currency: String) -> CostSummary
    // MTD: hours elapsed this month (or since createdAt if later) × hourly, capped at monthlyCap; monthlyFlat prorated? NO — flat = full month in projection, MTD = elapsed fraction
}
```

### Store (`Hetzly/Store/`) — Worker B

```swift
@Model final class ProjectRecord { @Attribute(.unique) var id: UUID; var name: String; var createdAt: Date; var sortOrder: Int }
// Token NEVER stored here — Keychain via TokenVault, account = id.uuidString
@Model final class ServerSnapshotRecord { var projectID: UUID; var payload: Data; var updatedAt: Date }  // JSON-encoded [Server]
@MainActor @Observable final class ProjectsStore {
    init(context: ModelContext)
    private(set) var projects: [ProjectRecord]
    func addProject(name: String, token: String) throws -> ProjectRecord   // saves token to TokenVault
    func rename(_ project: ProjectRecord, to: String)
    func remove(_ project: ProjectRecord) throws                            // deletes token + snapshots too
    func token(for project: ProjectRecord) throws -> String?
}
@MainActor final class SnapshotStore {
    init(context: ModelContext)
    func saveServers(_ servers: [Server], projectID: UUID)
    func loadServers(projectID: UUID) -> (servers: [Server], updatedAt: Date)?
}
static func hetzlyModelContainer() throws -> ModelContainer   // free func or on an enum; schema = both models
```

### App shell (`Hetzly/App/`, `Hetzly/Features/Onboarding/`, `Hetzly/Features/Settings/`) — Worker C

```swift
@MainActor @Observable final class AppContainer {
    static func makeDefault() -> AppContainer
    var projectsStore: ProjectsStore { get }
    var modelContainer: ModelContainer { get }
    func cloudClient(for projectID: UUID) -> CloudClient?     // cached per project; nil if token missing
    func snapshotStore() -> SnapshotStore
    var settings: AppSettings                                  // @Observable: requireBiometricsForDestructive: Bool, mascotEnabled: Bool (AppStorage-backed)
    let biometricGate: BiometricGate
}
// Injection: WindowGroup { RootView().environment(container) }; consumers: @Environment(AppContainer.self)
struct RootView: View        // no projects → OnboardingView; else MainTabView
struct MainTabView: View     // Tabs: Dashboard (DashboardView()), Resources placeholder, Costs placeholder, Settings (SettingsView)
```

### Dashboard (`Hetzly/Features/Dashboard/`) — Worker D
`struct DashboardView: View` — init(), reads `@Environment(AppContainer.self)`. Navigates to Server Detail via `NavigationStack` + `.navigationDestination(for: ServerRoute.self)`. `ServerRoute` (Hashable: projectID UUID, serverID Int, defined in Dashboard, used by detail).

### Server Detail (`Hetzly/Features/Servers/`) — Worker E
`struct ServerDetailView: View { init(route: ServerRoute) }` — reads container from environment, loads server, renders detail. Worker D's dashboard calls this via navigationDestination — Worker D declares the destination mapping `ServerRoute -> ServerDetailView(route:)`.

## M2 Wave A contracts (Cloud API full coverage — package layer)

All wave-1/2 code is committed and real — read it. Conventions for extending the package:

- Each resource gets its own model file in `CloudAPI/` (same rules: explicit CodingKeys, unknown-tolerant enums, Sendable, public memberwise inits).
- Client methods are added as `extension CloudClient` in per-area files named `CloudClient+<Area>.swift`. Method naming: `listVolumes()`, `createVolume(...) -> (Volume, Action?)`, `deleteVolume(id:)`, action methods `attachVolume(id:serverID:automount:) -> Action` etc.
- Requests with bodies: build `Data` via `JSONEncoder` with explicit `CodingKeys` request structs (snake_case spelled out), defined `internal` next to the extension.
- Every Hetzner "actions" response returns `Action` — reuse the existing envelope pattern (see CloudClient.swift).
- Tests: new files `CloudAPI<Area>Tests.swift` reusing `MockTransport`; never modify existing test files.
- File ownership per worker is disjoint — do NOT edit CloudClient.swift or another worker's files.

Binding client surface per area (wave-B features consume these):
- Servers+: `createServer(CreateServerRequest) -> CreateServerResult(server, action, rootPassword?)`, `rebuild(serverID:imageIDOrName:)`, `changeType(serverID:serverTypeID:upgradeDisk:)`, `enableRescue(serverID:sshKeyIDs:) -> (rootPassword, Action)`, `disableRescue`, `enableBackups`, `disableBackups`, `createImage(serverID:description:type:)`, `changeProtection(serverID:delete:rebuild:)`, `resetPassword(serverID:) -> (rootPassword, Action)`, `requestConsole(serverID:) -> (wssURL, password, Action)`, `rename(serverID:name:)`, `updateLabels(serverID:labels:)`, `attachISO/detachISO`, `listISOs`, `listServerTypes`, `listImages(type:)`, `deleteImage`, `updateImage(id:description:labels:)`, `changeImageProtection`, `listLocations`, `listDatacenters`
- Volumes/Networks: `listVolumes/createVolume/deleteVolume/resizeVolume/attachVolume/detachVolume/changeVolumeProtection/updateVolumeLabels`; `listNetworks/createNetwork/deleteNetwork/addSubnet/deleteSubnet/addRoute/deleteRoute/attachServerToNetwork/detachServerFromNetwork/updateNetwork`; `listPlacementGroups/createPlacementGroup/deletePlacementGroup`
- Firewalls/IPs: `listFirewalls/createFirewall/deleteFirewall/setFirewallRules/applyFirewall(toServerIDs:labelSelectors:)/removeFirewallFrom...`; `listPrimaryIPs/createPrimaryIP/deletePrimaryIP/assignPrimaryIP/unassignPrimaryIP/changePrimaryIPProtection/setPrimaryIPRDNS`; `listFloatingIPs/...same pattern.../setFloatingIPRDNS`
- Keys/Certs/LB/DNS: `listSSHKeys/createSSHKey(name:publicKey:)/deleteSSHKey/updateSSHKey`; `listCertificates/createManagedCertificate/uploadCertificate/deleteCertificate`; `listLoadBalancers/createLoadBalancer/deleteLoadBalancer/addLBService/deleteLBService/addLBTarget/removeLBTarget/attachLBToNetwork/detachLBFromNetwork/changeLBAlgorithm/changeLBType/loadBalancerMetrics(...)-> ServerMetrics-shaped`; DNS zones/records per current Hetzner DNS API (verify docs; separate `DNSClient` if base URL differs — token auth per docs)

App-target (M2 Wave A worker 5):
- `Hetzly/Security/SSHKeyGenerator.swift`: `enum SSHKeyGenerator { static func generateEd25519(comment: String) -> GeneratedSSHKey }` — CryptoKit Curve25519.Signing; `GeneratedSSHKey { publicKeyOpenSSH: String ("ssh-ed25519 AAAA... comment"), privateKeyOpenSSH: String (OpenSSH PEM format), fingerprintSHA256: String }`; store private key via KeychainStore service "com.hetzly.ssh-private-key" account = key name.
- `Pricing/CostItemBuilder` extension: `items(volumes:pricing:)`, `items(primaryIPs:pricing:)`, `items(loadBalancers:pricing:)` following the server pattern (own file `CostItemBuilder+Resources.swift`).

## M2 Wave B contracts (feature layer)

- Wave-B workers do NOT touch `Hetzly/App/` — tab wiring happens at integration. Binding view entry points: `CreateServerFlow(projectID: UUID, onCreated: @escaping (Server) -> Void)` (sheet), `ResourcesHubView()` (reads AppContainer env, own NavigationStack), `CostsView()`, `InvoicesView()` (SafariView wrapper + explainer card).
- Server Detail M2 surface stays in `Hetzly/Features/Servers/` (same worker family owns it).
- Shared per-project selection for Resources/Costs: ~~each view exposes its own project picker via a `ProjectPickerChip` — implemented once in `Hetzly/Features/Resources/ProjectPickerChip.swift`, reused by Costs via `import` (same target).~~ **Superseded by Wave B B4 (picker unity):** all of Dashboard, Costs, and Resources now use `ProjectFilterBar` (`Hetzly/Features/Dashboard/ProjectFilterBar.swift`) for project scoping — identical chips-with-"All" behavior and >6-project collapse across all three tabs. `ProjectPickerChip` was retired/deleted. Resources still needs one project to list resources, so its "All" chip shows a "Select a Project" prompt rather than aggregating (single-select underneath, same component/behavior on the surface). Dedicated keeps its own `RobotAccountPickerChip` (Robot accounts aren't Cloud projects).

## M3 contracts (Robot / dedicated servers)

Robot Webservice: `https://robot-ws.your-server.de`, HTTP **Basic auth** (separate webservice user), JSON responses.
Hard client-side constraints (spec-mandated): max 1 login attempt when adding credentials (3 failures = 10-min IP ban),
ALL requests serialized through one queue, conservative budget (~150 req/h), 5-minute response cache, no background polling.

### RobotAPI (`Packages/HetznerKit/Sources/HetznerKit/RobotAPI/`) — package layer

```swift
public actor RobotClient {
    public init(username: String, password: String, transport: HTTPTransport = URLSessionTransport())
    // Serialized: one in-flight request at a time; token-bucket ~150/h; 5-min TTL cache on GETs (bypass via forceRefresh).
    public func validateCredentials() async throws            // exactly ONE GET /server; 401 → HetznerAPIError.unauthorized
    public func listServers(forceRefresh: Bool = false) async throws -> [RobotServer]
    public func server(number: Int) async throws -> RobotServer
    public func rename(serverNumber: Int, to name: String) async throws -> RobotServer
    public func resetOptions(serverNumber: Int) async throws -> RobotResetInfo   // GET /reset/{n}
    public func reset(serverNumber: Int, type: RobotResetType) async throws      // POST /reset/{n} type=sw|hw|man
    public func wake(serverNumber: Int) async throws                              // POST /wol/{n}
    public func rescue(serverNumber: Int) async throws -> RobotRescue             // GET  /boot/{n}/rescue
    public func enableRescue(serverNumber: Int, os: String, sshKeyFingerprints: [String]) async throws -> RobotRescue // POST (password in response!)
    public func disableRescue(serverNumber: Int) async throws -> RobotRescue      // DELETE
    public func bootConfiguration(serverNumber: Int) async throws -> RobotBootConfiguration // GET /boot/{n}
    public func rdns(ip: String) async throws -> RobotRDNS                        // GET /rdns/{ip}
    public func setRDNS(ip: String, ptr: String) async throws -> RobotRDNS        // POST/PUT
    public func deleteRDNS(ip: String) async throws
    public func listIPs() async throws -> [RobotIP]                               // GET /ip
    public func listSubnets() async throws -> [RobotSubnet]                       // GET /subnet
    public func listSSHKeys() async throws -> [RobotSSHKey]                       // GET /key
    // Ordering (M3 worker 2):
    public func listProducts() async throws -> [RobotProduct]                     // GET /order/server/product (standard)
    public func listMarketProducts() async throws -> [RobotMarketProduct]         // GET /order/server_market/product
    public func orderServer(_ order: RobotServerOrder) async throws -> RobotTransaction        // POST /order/server
    public func orderMarketServer(_ order: RobotMarketOrder) async throws -> RobotTransaction  // POST /order/server_market
    public func listTransactions() async throws -> [RobotTransaction]             // GET /order/server/transaction (+ market)
    public func transaction(id: String) async throws -> RobotTransaction
}
```
Robot JSON quirks (models must handle): list endpoints return `[{"server": {...}}, ...]` (each element wrapped);
single endpoints return `{"server": {...}}`. Errors: `{"error": {"status": 404, "code": "SERVER_NOT_FOUND", "message": "..."}}`
→ map to HetznerAPIError (reuse Core). 403 with code "NOT_ALLOWED"/ordering-disabled → HetznerAPIError.forbidden with the code preserved in the message.
Key models: `RobotServer` (serverNumber Int ("server_number"), serverName, product, dc, traffic, status ready/in process, cancelled Bool, paidUntil String?, serverIP String?, serverIPv6Net String?, subnet/ip arrays optional), `RobotResetType` sw/hw/man (+ per-type availability from RobotResetInfo.type [String]), `RobotRescue` (os, active Bool, password String? — SECRET, boot config), `RobotRDNS` (ip, ptr), `RobotIP`/`RobotSubnet`, `RobotSSHKey` (name, fingerprint, data), `RobotProduct` (id, name, description [String], traffic, dist [String], price/priceSetup Decimal-bearing strings + location list), `RobotMarketProduct` (id, name, cpu, memorySize, hddSize/hddText, price, priceSetup, fixedPrice Bool, nextReduce timestamps), `RobotServerOrder`/`RobotMarketOrder` (productID, authorizedKeys [String] fingerprints, dist?, location?, test Bool — ALWAYS default test=true in the type; UI must explicitly set false), `RobotTransaction` (id, date, status "in process"/"ready"/"cancelled", serverNumber Int?, product summary).

### App layer (M3)

- `RobotAccountsStore` (Hetzly/Store/RobotAccountsStore.swift — worker 3): SwiftData `RobotAccountRecord { id UUID, label String, username String, createdAt }`
  (password ONLY in Keychain via TokenVault.robotCredentials, account = id.uuidString). @MainActor @Observable, add/rename/remove; AppContainer gains
  `var robotAccountsStore` + `func robotClient(for accountID: UUID) -> RobotClient?` (cached) — worker 3 edits AppContainer (owns that edit this wave) and
  registers the new @Model in hetzlyModelContainer()'s schema (edit Hetzly/Store/HetzlyModelContainer.swift).
- `DedicatedView()` (Hetzly/Features/Dedicated/ — worker 3): 5th tab (integrator wires the Tab). Account picker chip when >1 account.
- Ordering UI (Hetzly/Features/Dedicated/Ordering/ — worker 4): entry from DedicatedView toolbar ("Order server", cart icon). Binding name: `OrderServerFlow()`.
  Order placement is ALWAYS Face-ID-gated (regardless of the destructive-actions setting) and double-confirmed (review screen → typed "ORDER" or explicit
  armed toggle → Face ID → place). Default test-mode order first is NOT exposed to users; the client type defaults test=true and the final placement sets test=false explicitly.
- Costs (worker 5): Robot servers auto-listed in Costs with per-server manual €/mo (persisted, keyed by server number in ManualCostStore-style UserDefaults JSON,
  distinct store: `DedicatedPriceStore`); Dashboard gets a "DEDICATED" section listing robot servers (status dot: ready/in-process) when accounts exist.

## Multi-project wave contracts (post-M4)

Binding cross-worker touchpoints:

```swift
// Hetzly/Features/Projects/ (Worker P2)
struct ProjectRoute: Hashable, Codable { let projectID: UUID }
struct ProjectDetailView: View { init(route: ProjectRoute) }   // reads AppContainer from environment

// Hetzly/Features/Dashboard/ProjectFilterBar.swift (Worker P1; reusable within the app target)
struct ProjectFilterBar: View {
    init(projects: [ProjectRecord], selection: Binding<UUID?>, onAddProject: @escaping () -> Void)
    // nil selection = "All". Horizontal chip bar; >6 projects → picker menu chip instead of endless chips.
}

// Hetzly/Store/ProjectsStore.swift additions (Worker P4)
func updateToken(for project: ProjectRecord, to newToken: String) throws   // Keychain replace, no record change
func move(fromOffsets: IndexSet, toOffset: Int)                            // persists sortOrder

// Hetzly/App/AppContainer.swift addition (Worker P4)
func invalidateCloudClient(for projectID: UUID)   // drops the cached client (call after token update)
```

Navigation: Dashboard project section headers and Costs project section headers become NavigationLinks
to `ProjectRoute`; each NavigationStack owner registers `.navigationDestination(for: ProjectRoute.self)`.
Token-revoked UX: a 401-failing project section shows an "Update token" affordance that presents the
token-update sheet (Worker P4's `UpdateTokenSheet(project:)` in Features/Settings/, reusable).

## Final-features wave contracts

### StorageBoxAPI (`Packages/HetznerKit/Sources/HetznerKit/StorageBoxAPI/`) — worker F1
```swift
public actor StorageBoxClient {
    public init(token: String, transport: HTTPTransport = URLSessionTransport())
    // base https://api.hetzner.com/v1 — VERIFY against current docs before building; Bearer auth
    public func validateToken() async throws
    public func listStorageBoxes() async throws -> [StorageBox]
    public func storageBox(id: Int) async throws -> StorageBox
    // + folders/usage/snapshots/subaccounts/settings/resetPassword per current docs — match real API, contract defers to docs
}
```
Models per real docs (unknown-tolerant enums, lenient labels via CloudAPICompat helpers, explicit CodingKeys).

### Storage Boxes app layer — worker F3
- `StorageBoxAccountRecord` (@Model: id UUID, label, createdAt; token in Keychain service "com.hetzly.storagebox-token", account = id) + `StorageBoxAccountsStore` (mirror RobotAccountsStore) in Hetzly/Store/; register in schema + AppContainer (`storageBoxAccountsStore`, `storageBoxClient(for:)`).
- `StorageBoxesView()` (Hetzly/Features/StorageBoxes/) — entry row added at integration to ResourcesHubView (account-scoped, not project-scoped). Settings gains a "Storage Box accounts" section (mirror Robot accounts UX).

### Robot vSwitch + failover (`RobotAPI/`) — worker F2
`extension RobotClient`: listVSwitches/vSwitch(id:)/createVSwitch(name:vlan:)/updateVSwitch/deleteVSwitch(id:)/addVSwitchServers/removeVSwitchServers; listFailoverIPs/failoverIP(ip:)/switchFailover(ip:to:) — per robot docs (form-encoded, wrapped JSON). UI (worker F4): sections in Dedicated tab.

### CSV export — worker F4
`CostsCSVExporter` (Hetzly/Features/Costs/): builds CSV (project, name, kind, monthly projected, MTD, currency) from CostsViewModel state → ShareLink file export (CSV via `FileRepresentation`/temp file). Toolbar menu on CostsView: Share image / Export CSV.

### Adaptive colors (light mode) — worker F5
`HetzlyColors` entries become adaptive `Color(uiColor: UIColor { trait ... })` — dark values UNCHANGED (current hex), light variants: canvas #F5F5F7, textPrimary #1D1D1F, textSecondary #6E6E73, textTertiary #AEAEB2, accent unchanged, destructive unchanged, status colors unchanged. CanvasBackground + GlassCard/GlassChip fallback fills adapt via trait too. Mascot palette stays fixed (sprite art). Every #Preview keeps .dark; add a handful of light previews on key screens.

## Server-page wave contracts

### Terminal module (`Hetzly/Features/Terminal/`) — worker SP1
Adds SPM deps (user explicitly approved, overriding zero-dep for this feature):
- `apple/swift-nio-ssh` (SSH protocol) + its NIO transitive deps.
- `migueldeicaza/SwiftTerm` (terminal emulator UIView).
Both added to project.yml `packages:` and the Hetzly target `dependencies:`. Pin to versions that build on iOS 26.

Binding entry:
```swift
struct ServerTerminalView: View {
    init(host: String, port: Int = 22, username: String = "root", credential: SSHCredential, serverName: String)
}
enum SSHCredential { case privateKeyPEM(String), password(String) }
```
Full-screen cover. Connects via NIO-SSH, opens a shell channel with a PTY, pipes to a SwiftTerm `TerminalView` (UIViewRepresentable). States: connecting / connected / auth-failed / unreachable / closed, each with clear copy. Host-key: trust-on-first-use, persisted per host in UserDefaults (fingerprint only), with a mismatch warning. NEVER log key material or session bytes. Disconnect on dismiss. Ed25519 private keys from Hetzly's generator are OpenSSH-PEM — NIO-SSH needs them as `NIOSSHPrivateKey`; convert (the key is Curve25519; use the raw seed). If PEM→NIOSSHPrivateKey is impractical, fall back to password auth and report the limitation precisely.

### Server page restructure (`Hetzly/Features/Servers/`) — worker SP2
Restructure `ServerDetailView` into a segmented **Control / Analytics** layout (glass segmented picker under the hero):
- **Control tab**: the power action row, protection toggle, Backups & Snapshots, Rescue Mode, ISO, rename/labels, and the Danger Zone — everything that acts on the server, grouped.
- **Analytics tab**: the metrics charts + range picker only.
- Hero card stays above the segmented control (always visible).
- Add a **Terminal** button (in Control, near the action row): presents `ServerTerminalView` (SP1) using the server's public IPv4, username root, and a credential resolved from: stored SSH private key for a key on the server if available, else the saved root password from `ServerCredentialsVault`, else prompt. If neither exists, the button explains "No stored credentials — add an SSH key or reset the root password first."
- Add a **Credentials** section/row in Control: if `ServerCredentialsVault.rootPassword(serverID:)` exists, show it via `SensitiveSecretCard` (biometric-gated reveal), with Delete. Wire vault SAVES at the reset-root-password and enable-rescue result points (both already produce a password in ServerDetailViewModel).
- Keep every existing action + test working; keep the A1/A2 credential-vault + error-recovery code intact.

## Pricing-accuracy + server-data wave

Root cause (confirmed live, see memory hetzner-no-per-server-price): the Hetzner API exposes NO
actual/grandfathered per-server price — `/servers/{id}` has no price field; `/pricing` is current
list price only. So grandfathered servers over-report. Fix = manual per-server override, mirroring
the existing `DedicatedPriceStore`.

### Binding shared type — worker PA owns the file, PB consumes
`Hetzly/Features/Costs/CloudServerPriceStore.swift` (mirror `DedicatedPriceStore.swift` exactly):
```swift
struct CloudServerPriceEntry: Codable, Identifiable, Sendable, Equatable { var serverNumber: Int; var monthlyPrice: Decimal; var note: String?; var id: Int { serverNumber } }
@MainActor @Observable final class CloudServerPriceStore {
    init(defaults: UserDefaults = .standard)   // key "com.hetzly.costs.cloudServerPrices"
    private(set) var entries: [CloudServerPriceEntry]
    func price(for serverNumber: Int) -> Decimal?
    func setPrice(serverNumber: Int, monthlyPrice: Decimal, note: String?)
    func removePrice(for serverNumber: Int)
}
```

### Cost integration — worker PA
- `CostItemBuilder.items(servers:pricing:overrides:)` — add `overrides: [Int: Decimal] = [:]` (serverID→user monthly). When an override exists for a server, emit `CostItem(.server, .monthlyFlat(net: override))` instead of the list-price hourly item (skip the backup surcharge recalculation? keep backups off the overridden base — document). Default empty = current behavior, so all existing call sites/tests compile unchanged.
- Thread the overrides dict (from `CloudServerPriceStore.entries`) through `CostsViewModel`, `DashboardViewModel` (perProjectBurn + combined + widget snapshot stays LIST price? NO — use override for accuracy), and `ProjectDetailViewModel`.
- Costs UI: in the per-project cost rows / breakdown, add an "edit price" affordance per Cloud server (like the dedicated "Set price"), presenting a `CloudServerPriceSheet` (net €/mo + note + "Clear override"). Show list-vs-your-price when an override is set.

### Server-page data — worker PB (`Hetzly/Features/Servers/`)
On the server detail Control tab / hero (`ServerHeroCard` + `ServerDetailViewModel`):
- **Price row**: effective monthly (override if set else list price from `/pricing` for the server's type+location — `ServerDetailViewModel` loads `pricing()` cached). If an override is set and differs from list, show both ("You pay €25.49 · list €69.49"). Tap → `CloudServerPriceSheet` (reuse PA's sheet if it's shared, else a local one — coordinate: PA puts the sheet in Costs/; PB may need its own presentation — a small shared `CloudServerPriceSheet` in Costs/ referenced from both is cleanest; if PA hasn't landed, PB defines a minimal local editor and notes it).
- **Traffic usage row**: `server.outgoingTraffic`/`ingoingTraffic`/`includedTraffic` (bytes, may be nil) → "1.2 TB out · 340 GB in · 20 TB included" with a thin usage bar (out vs included); omit gracefully if nil.
- **IPv6 copy**: `ServerHeroCard` currently copies IPv4 — add the IPv6 address (`server.publicNet.ipv6?.ip`, a CIDR) as a second tap-to-copy row with the same checkmark/haptic pattern. Keep IPv4.

## Wave B (systemic) contracts — spawned after the pricing wave integrates
- B1 accent discipline: `Assets.xcassets/AccentColor.colorset` → neutral (textPrimary gray); explicit `.tint(HetzlyColors.accent)` only on true CTAs; shared `SheetHeaderBadge`; chart primary series → monochrome (accent reserved for threshold/attention). DesignSystem + sweep.
- B2 offline parity: generalize `SnapshotStore` into a `DiskCache<T>` behind `ResourceListModel` + Dedicated/Costs/StorageBoxes load states (stale-while-revalidate + stale chip), reusing Dashboard's freshness pattern.
- B3 notifications: `UNUserNotificationCenter` local notification when a tracked `ActionTracker` action completes while backgrounded; permission ask; no background polling.
- B4 deep links + picker unity: `hetzly://` URL scheme + `onOpenURL` routing to ServerRoute/ProjectRoute; widget `widgetURL`; reuse `ProjectFilterBar` in Resources (retire the divergent `ProjectPickerChip` behavior).

## Verification expected from each worker

- HetznerKit workers: `cd Packages/HetznerKit && swift build && swift test` must pass.
- App-target workers: each Swift file must parse against the iOS SDK:
  `xcrun swiftc -parse -sdk $(xcrun --show-sdk-path --sdk iphonesimulator) -target arm64-apple-ios26.0-simulator <files>`
  (cross-file references may not resolve in isolation — that's fine; syntax and imports must.)
