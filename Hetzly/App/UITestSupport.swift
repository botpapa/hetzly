#if DEBUG
import Foundation
import HetznerKit
import SwiftData

/// UI-test-only support, compiled only into Debug builds and gated again at
/// runtime by an explicit launch-environment flag — this can never affect a
/// Release/TestFlight/App Store build, and never runs on a normal Debug
/// launch either.
///
/// `HetzlyUITests` sets one of two flags before `-launch()`:
/// - `HETZLY_UITEST=1` — an in-memory store pre-seeded with one "Demo
///   Project" whose `CloudClient` is routed through `UITestTransport`, a
///   canned-fixture router that answers every request the dashboard,
///   server detail, and create-server wizard make without touching the
///   network. `TokenVault`/Keychain is fully bypassed: the seed inserts a
///   `ProjectRecord` straight into the in-memory SwiftData context (before
///   `AppContainer`/`ProjectsStore` construction, so the store's initial
///   fetch sees it) and pre-caches the fixture client under that project's
///   id — no token is ever stored or validated. Necessarily so: UI-test
///   builds run with `CODE_SIGNING_ALLOWED=NO`, and keychain writes fail in
///   an unsigned app.
/// - `HETZLY_UITEST_MULTI=1` — like `HETZLY_UITEST` but seeds TWO projects
///   ("Production" and "Staging"), each with its own fixture client, to
///   exercise the multi-project aggregation paths (per-project dashboard
///   sections, combined cost burn). A separate flag so the single-project
///   tests keep the "+" button's single-project shortcut behavior.
/// - `HETZLY_UITEST_EMPTY=1` — an in-memory store with nothing seeded, so
///   `RootView` shows onboarding.
enum UITestSupport {
    private static let seedEnvironmentKey = "HETZLY_UITEST"
    private static let multiSeedEnvironmentKey = "HETZLY_UITEST_MULTI"
    private static let emptyEnvironmentKey = "HETZLY_UITEST_EMPTY"

    private static var isSeedRequested: Bool {
        ProcessInfo.processInfo.environment[seedEnvironmentKey] == "1"
    }

    private static var isMultiSeedRequested: Bool {
        ProcessInfo.processInfo.environment[multiSeedEnvironmentKey] == "1"
    }

    private static var isEmptyRequested: Bool {
        ProcessInfo.processInfo.environment[emptyEnvironmentKey] == "1"
    }

    /// `nil` on every launch except one `HetzlyUITests` explicitly flagged.
    /// `@MainActor` because it constructs an `AppContainer`, whose
    /// initializer is main-actor-isolated (it isn't inferred here the way it
    /// is for `HetzlyApp`'s own members, since this is a plain top-level
    /// `enum`, not a `View`/`App` conformance).
    @MainActor
    static func makeContainerIfRequested() -> AppContainer? {
        if isSeedRequested {
            let modelContainer = inMemoryModelContainer()

            // Seed the demo project directly into the context BEFORE the
            // AppContainer (and therefore ProjectsStore) is constructed, so
            // the store's initial fetch already sees it. The fixture client
            // is keyed by the same record id; no token/Keychain involved.
            let project = ProjectRecord(name: "Demo Project", sortOrder: 0)
            modelContainer.mainContext.insert(project)
            try? modelContainer.mainContext.save()

            let fixtureClient = CloudClient(
                token: "uitest-fake-token-never-sent",
                transport: UITestTransport()
            )
            return AppContainer.makeForUITesting(
                modelContainer: modelContainer,
                preconfiguredCloudClients: [project.id: fixtureClient]
            )
        }
        if isMultiSeedRequested {
            let modelContainer = inMemoryModelContainer()

            let production = ProjectRecord(name: "Production", sortOrder: 0)
            let staging = ProjectRecord(name: "Staging", sortOrder: 1)
            modelContainer.mainContext.insert(production)
            modelContainer.mainContext.insert(staging)
            try? modelContainer.mainContext.save()

            // Each project gets its own client instance (mirroring the real
            // per-project cache) AND its own server-name pair, so the two
            // sections are visually and assertably distinct rather than both
            // showing "web-01"/"worker-02" twice.
            return AppContainer.makeForUITesting(
                modelContainer: modelContainer,
                preconfiguredCloudClients: [
                    production.id: CloudClient(
                        token: "uitest-fake-token-never-sent",
                        transport: UITestTransport(serverNames: ["web-01", "worker-02"])
                    ),
                    staging.id: CloudClient(
                        token: "uitest-fake-token-never-sent",
                        transport: UITestTransport(serverNames: ["api-01", "cache-02"])
                    ),
                ]
            )
        }
        if isEmptyRequested {
            return AppContainer.makeForUITesting(
                modelContainer: inMemoryModelContainer(),
                preconfiguredCloudClients: [:]
            )
        }
        return nil
    }

    private static func inMemoryModelContainer() -> ModelContainer {
        let schema = Schema([ProjectRecord.self, ServerSnapshotRecord.self, RobotAccountRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
            return container
        }
        // Unreachable in practice — an in-memory store performs no disk I/O,
        // so construction only fails for a structural schema defect, which
        // would fail identically in `AppContainer.buildModelContainer`'s own
        // fallback (see the rationale there). This helper is test-support
        // code, reachable only under `#if DEBUG` plus an explicit UI-test
        // launch-environment flag, so it never ships.
        // swiftlint:disable:next force_try
        return try! ModelContainer(for: schema, configurations: [configuration])
    }
}

// MARK: - Canned-fixture transport

/// Routes every `HTTPTransport` request the demo project's `CloudClient`
/// makes to inline JSON fixtures instead of the network, matched on HTTP
/// method + path (query strings are inspected only where a real endpoint's
/// behavior depends on them, e.g. `/images?type=`). Stateless — every
/// response is a pure function of the request, including the create-server
/// flow: `POST /servers` echoes the requested name back, and `GET
/// /actions/{id}` always reports `success` immediately (the wizard's
/// `ActionTracker` polls once and is done), so the wizard's happy path never
/// needs to wait out real polling cadence.
struct UITestTransport: HTTPTransport {
    /// The two fixture servers' names — `[runningServerName, offServerName]`.
    /// Defaults to the original single-project fixture names so every
    /// pre-existing test (and any call site that doesn't care) is unaffected.
    /// `HETZLY_UITEST_MULTI` gives each project's client a distinct pair so
    /// Production and Staging sections are visually and assertably distinct.
    let serverNames: [String]

    init(serverNames: [String] = ["web-01", "worker-02"]) {
        self.serverNames = serverNames
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw URLError(.badURL) }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = (components?.path ?? url.path)
            .split(separator: "/")
            .map(String.init)
            .drop(while: { $0 == "v1" })
        let query = components?.queryItems ?? []
        let method = request.httpMethod ?? "GET"

        let body = UITestFixtures.response(
            method: method, path: Array(path), query: query, requestBody: request.httpBody, serverNames: serverNames
        )
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:]) else {
            throw URLError(.badServerResponse)
        }
        return (body, response)
    }
}

// MARK: - Fixtures

/// Realistic Hetzner Cloud API JSON, adapted from
/// `Packages/HetznerKit/Tests/HetznerKitTests/CloudAPIFixtures.swift` (same
/// wire shapes, trimmed to what the app's UI-test surface actually reads).
/// Two demo servers (`web-01` running, `worker-02` off by default — see
/// `UITestTransport.serverNames` for how `HETZLY_UITEST_MULTI` overrides
/// these per project) at `fsn1`/`nbg1`, a
/// three-location catalog with `fsn1` sorting first (matching
/// `CreateServerViewModel`'s city-name sort — the UI test's "first location
/// card"), and `cx22` priced cheapest everywhere it's sold (the UI test's
/// "first server type row").
enum UITestFixtures {
    static let runningServerID = 5101
    static let offServerID = 5102
    static let createdServerID = 5201
    static let createActionID = 5301

    static func response(
        method: String, path: [String], query: [URLQueryItem], requestBody: Data?,
        serverNames: [String] = ["web-01", "worker-02"]
    ) -> Data {
        switch method {
        case "GET":
            if path == ["pricing"] { return pricingJSON }
            if path == ["servers"] { return serversListJSON(serverNames: serverNames) }
            if path.count == 2, path[0] == "servers", let id = Int(path[1]) {
                return serverEnvelopeJSON(id: id, serverNames: serverNames)
            }
            if path.count == 3, path[0] == "servers", path[2] == "metrics" { return metricsJSON }
            if path == ["locations"] { return locationsJSON }
            if path == ["images"] { return imagesJSON(query: query) }
            if path == ["server_types"] { return serverTypesJSON }
            if path == ["ssh_keys"] { return sshKeysJSON }
            if path == ["networks"] { return networksJSON }
            if path == ["firewalls"] { return firewallsJSON }
            if path.count == 2, path[0] == "actions" { return actionSuccessJSON(id: Int(path[1]) ?? createActionID) }
        case "POST":
            if path == ["servers"] { return createServerResponseJSON(requestBody: requestBody) }
        default:
            break
        }
        return Data("{}".utf8)
    }

    // MARK: Shared fragments

    private static let fsn1LocationJSON = """
    {"id": 1, "name": "fsn1", "description": "Falkenstein DC Park 1", "country": "DE", "city": "Falkenstein", "latitude": 50.47, "longitude": 12.37, "network_zone": "eu-central"}
    """
    private static let nbg1LocationJSON = """
    {"id": 2, "name": "nbg1", "description": "Nuremberg DC Park 1", "country": "DE", "city": "Nuremberg", "latitude": 49.45, "longitude": 11.07, "network_zone": "eu-central"}
    """
    private static let hel1LocationJSON = """
    {"id": 3, "name": "hel1", "description": "Helsinki DC Park 1", "country": "FI", "city": "Helsinki", "latitude": 60.17, "longitude": 24.94, "network_zone": "eu-central"}
    """

    private static let fsn1DatacenterJSON = """
    {"id": 1, "name": "fsn1-dc14", "description": "Falkenstein 1 DC14", "location": \(fsn1LocationJSON)}
    """
    private static let nbg1DatacenterJSON = """
    {"id": 2, "name": "nbg1-dc3", "description": "Nuremberg DC Park 3", "location": \(nbg1LocationJSON)}
    """

    private static func serverTypePricesJSON(monthly: String) -> String {
        let hourly = "0.0060"
        return """
        [
            {"location": "fsn1", "price_hourly": {"net": "\(hourly)", "gross": "\(hourly)"}, "price_monthly": {"net": "\(monthly)", "gross": "\(monthly)"}},
            {"location": "nbg1", "price_hourly": {"net": "\(hourly)", "gross": "\(hourly)"}, "price_monthly": {"net": "\(monthly)", "gross": "\(monthly)"}},
            {"location": "hel1", "price_hourly": {"net": "\(hourly)", "gross": "\(hourly)"}, "price_monthly": {"net": "\(monthly)", "gross": "\(monthly)"}}
        ]
        """
    }

    /// Cheapest of the two — this is the type the "pick first server type
    /// row" UI-test step taps.
    private static let cx22JSON = """
    {
        "id": 22, "name": "cx22", "description": "CX22", "cores": 2, "memory": 4.0, "disk": 40,
        "cpu_type": "shared", "architecture": "x86", "deprecated": false,
        "prices": \(serverTypePricesJSON(monthly: "3.79"))
    }
    """
    private static let cx32JSON = """
    {
        "id": 32, "name": "cx32", "description": "CX32", "cores": 4, "memory": 8.0, "disk": 80,
        "cpu_type": "shared", "architecture": "x86", "deprecated": false,
        "prices": \(serverTypePricesJSON(monthly: "6.90"))
    }
    """

    private static func serverJSON(
        id: Int,
        name: String,
        status: String,
        datacenter: String,
        serverType: String,
        ipv4: String
    ) -> String {
        """
        {
            "id": \(id),
            "name": "\(name)",
            "status": "\(status)",
            "created": "2024-01-01T00:00:00+00:00",
            "public_net": {
                "ipv4": {"ip": "\(ipv4)"},
                "ipv6": {"ip": "2001:db8:1::/64"}
            },
            "server_type": \(serverType),
            "datacenter": \(datacenter),
            "labels": {},
            "locked": false,
            "protection": {"delete": false, "rebuild": false},
            "backup_window": null,
            "rescue_enabled": false,
            "primary_disk_size": 40,
            "included_traffic": 21990232555520,
            "outgoing_traffic": null,
            "ingoing_traffic": null
        }
        """
    }

    /// `names[0]` is the running server's name, `names[1]` the off server's —
    /// falling back to the original fixed names if a caller passes something
    /// shorter than 2 elements, so this never crashes on a malformed override.
    private static func runningServerJSON(name: String) -> String {
        serverJSON(
            id: runningServerID, name: name, status: "running",
            datacenter: fsn1DatacenterJSON, serverType: cx22JSON, ipv4: "95.216.1.10"
        )
    }
    private static func offServerJSON(name: String) -> String {
        serverJSON(
            id: offServerID, name: name, status: "off",
            datacenter: nbg1DatacenterJSON, serverType: cx22JSON, ipv4: "95.216.1.11"
        )
    }

    static func serversListJSON(serverNames: [String] = ["web-01", "worker-02"]) -> Data {
        let running = runningServerJSON(name: serverNames.first ?? "web-01")
        let off = offServerJSON(name: serverNames.count > 1 ? serverNames[1] : "worker-02")
        return Data("{\"servers\": [\(running), \(off)]}".utf8)
    }

    static func serverEnvelopeJSON(id: Int, serverNames: [String] = ["web-01", "worker-02"]) -> Data {
        let body: String
        switch id {
        case runningServerID: body = runningServerJSON(name: serverNames.first ?? "web-01")
        case offServerID: body = offServerJSON(name: serverNames.count > 1 ? serverNames[1] : "worker-02")
        default:
            // Never expected on the UI-test happy path (the wizard's
            // `onCreated` callback re-lists rather than re-fetching by id),
            // but kept decodable rather than 404-ing so an unanticipated
            // lookup degrades gracefully instead of crashing the test.
            body = serverJSON(
                id: id, name: "server-\(id)", status: "running",
                datacenter: fsn1DatacenterJSON, serverType: cx22JSON, ipv4: "95.216.1.99"
            )
        }
        return Data("{\"server\": \(body)}".utf8)
    }

    static let locationsJSON = Data(
        "{\"locations\": [\(fsn1LocationJSON), \(hel1LocationJSON), \(nbg1LocationJSON)]}".utf8
    )

    static let serverTypesJSON = Data("{\"server_types\": [\(cx22JSON), \(cx32JSON)]}".utf8)

    private static func imageJSON(id: Int, name: String, flavor: String, version: String) -> String {
        """
        {
            "id": \(id), "type": "system", "status": "available", "name": "\(name)",
            "description": "\(flavor.capitalized) \(version)", "image_size": null, "disk_size": 10,
            "created": "2024-01-01T00:00:00+00:00", "created_from": null, "bound_to": null,
            "os_flavor": "\(flavor)", "os_version": "\(version)", "architecture": "x86",
            "protection": {"delete": false}, "deprecated": null, "labels": {}
        }
        """
    }

    /// Newest ubuntu image first — matches the real API's `sort=created:desc`
    /// and `ImageStepView`'s "expanding a flavor auto-selects the first
    /// (newest) image" behavior. This is the image id the UI test's "ubuntu
    /// flavor + version chip" step taps.
    private static let ubuntu2404JSON = imageJSON(id: 101, name: "ubuntu-24.04", flavor: "ubuntu", version: "24.04")
    private static let ubuntu2204JSON = imageJSON(id: 102, name: "ubuntu-22.04", flavor: "ubuntu", version: "22.04")
    private static let debian12JSON = imageJSON(id: 111, name: "debian-12", flavor: "debian", version: "12")

    static func imagesJSON(query: [URLQueryItem]) -> Data {
        // Every fixture image is `type: "system"`, so `type=snapshot` (asked
        // by Server Detail's backups section) correctly yields none, and
        // `type=system`/no filter yields the full catalog.
        let type = query.first(where: { $0.name == "type" })?.value
        guard type == nil || type == "system" else {
            return Data("{\"images\": []}".utf8)
        }
        return Data("{\"images\": [\(ubuntu2404JSON), \(ubuntu2204JSON), \(debian12JSON)]}".utf8)
    }

    static let sshKeysJSON = Data(
        """
        {"ssh_keys": [
            {"id": 1, "name": "uitest-key", "fingerprint": "aa:bb:cc:dd:ee:ff", "public_key": "ssh-ed25519 AAAAC3uitest", "labels": {}, "created": "2024-01-01T00:00:00+00:00"}
        ]}
        """.utf8
    )

    static let networksJSON = Data(
        """
        {"networks": [
            {"id": 1, "name": "prod-net", "ip_range": "10.0.0.0/16", "subnets": [], "routes": [], "servers": [], "protection": {"delete": false}, "labels": {}, "created": "2024-01-01T00:00:00+00:00", "expose_routes_to_vswitch": null}
        ]}
        """.utf8
    )

    static let firewallsJSON = Data(
        """
        {"firewalls": [
            {"id": 1, "name": "web-fw", "labels": {}, "created": "2024-01-01T00:00:00+00:00", "rules": [], "applied_to": []}
        ]}
        """.utf8
    )

    static let pricingJSON = Data(
        """
        {"pricing": {
            "currency": "EUR",
            "vat_rate": "19.00",
            "server_types": [
                {"id": 22, "name": "cx22", "prices": \(serverTypePricesJSON(monthly: "3.79"))},
                {"id": 32, "name": "cx32", "prices": \(serverTypePricesJSON(monthly: "6.90"))}
            ],
            "primary_ips": [],
            "volume": {"price_per_gb_month": {"net": "0.0400", "gross": "0.0400"}},
            "server_backup": {"percentage": "20.00"}
        }}
        """.utf8
    )

    static let metricsJSON = Data(
        """
        {"metrics": {
            "start": "2024-01-01T00:00:00Z",
            "end": "2024-01-01T01:00:00Z",
            "step": 60,
            "time_series": {
                "cpu": {"values": [[1704067200.0, "12.5"], [1704067260.0, "18.2"]]},
                "disk.0.iops.read": {"values": [[1704067200.0, "1.0"]]},
                "network.0.bandwidth.in": {"values": [[1704067200.0, "100"]]}
            }
        }}
        """.utf8
    )

    // MARK: Create-server flow

    private struct CreateServerNameProbe: Decodable {
        let name: String
    }

    private static func createdServerJSON(name: String) -> String {
        serverJSON(
            id: createdServerID, name: name, status: "initializing",
            datacenter: fsn1DatacenterJSON, serverType: cx22JSON, ipv4: "95.216.9.9"
        )
    }

    static func createServerResponseJSON(requestBody: Data?) -> Data {
        let name = requestBody
            .flatMap { try? JSONDecoder().decode(CreateServerNameProbe.self, from: $0) }
            .map(\.name) ?? "uitest-server"

        return Data(
            """
            {
                "server": \(createdServerJSON(name: name)),
                "action": {
                    "id": \(createActionID), "command": "create_server", "status": "running", "progress": 0,
                    "started": "2024-01-01T00:00:00+00:00", "finished": null,
                    "resources": [{"id": \(createdServerID), "type": "server"}], "error": null
                },
                "next_actions": [],
                "root_password": "fakeUITestPassword!1"
            }
            """.utf8
        )
    }

    /// Always reports `success` on the first poll — `ActionTracker` polls
    /// immediately with no upfront delay, so this resolves the wizard's
    /// "creating" phase without waiting out real polling cadence.
    static func actionSuccessJSON(id: Int) -> Data {
        Data(
            """
            {"action": {
                "id": \(id), "command": "create_server", "status": "success", "progress": 100,
                "started": "2024-01-01T00:00:00+00:00", "finished": "2024-01-01T00:00:05+00:00",
                "resources": [{"id": \(createdServerID), "type": "server"}], "error": null
            }}
            """.utf8
        )
    }
}
#endif
