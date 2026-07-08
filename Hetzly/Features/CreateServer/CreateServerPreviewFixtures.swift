import Foundation
import HetznerKit

/// Preview-only mock catalog data for the create-server wizard. No network
/// access — every `#Preview` in this directory renders from a
/// `CreateServerViewModel` seeded directly via its preview-state
/// initializer.
enum CreateServerPreviewFixtures {
    static let locations: [Location] = [
        Location(id: 1, name: "nbg1", description: "Nuremberg DC Park 1", country: "DE", city: "Nuremberg", latitude: 49.45, longitude: 11.07, networkZone: "eu-central"),
        Location(id: 2, name: "fsn1", description: "Falkenstein DC Park 1", country: "DE", city: "Falkenstein", latitude: 50.47, longitude: 12.37, networkZone: "eu-central"),
        Location(id: 3, name: "hel1", description: "Helsinki DC Park 1", country: "FI", city: "Helsinki", latitude: 60.17, longitude: 24.94, networkZone: "eu-central"),
        Location(id: 4, name: "ash", description: "Ashburn, VA", country: "US", city: "Ashburn", latitude: 39.04, longitude: -77.49, networkZone: "us-east"),
        Location(id: 5, name: "sin", description: "Singapore", country: "SG", city: "Singapore", latitude: 1.35, longitude: 103.82, networkZone: "ap-southeast"),
    ]

    static let images: [HetznerImage] = [
        image(id: 101, name: "ubuntu-24.04", flavor: "ubuntu", version: "24.04", arch: .x86, daysAgo: 10),
        image(id: 102, name: "ubuntu-22.04", flavor: "ubuntu", version: "22.04", arch: .x86, daysAgo: 400),
        image(id: 103, name: "ubuntu-24.04", flavor: "ubuntu", version: "24.04", arch: .arm, daysAgo: 10),
        image(id: 111, name: "debian-12", flavor: "debian", version: "12", arch: .x86, daysAgo: 40),
        image(id: 112, name: "debian-11", flavor: "debian", version: "11", arch: .x86, daysAgo: 500),
        image(id: 121, name: "fedora-40", flavor: "fedora", version: "40", arch: .x86, daysAgo: 20),
        image(id: 131, name: "rocky-9", flavor: "rocky", version: "9", arch: .x86, daysAgo: 60),
        image(id: 141, name: "alma-9", flavor: "alma", version: "9", arch: .x86, daysAgo: 60),
    ]

    static let serverTypes: [ServerType] = [
        serverType(id: 22, name: "cx22", cores: 2, memory: 4, disk: 40, cpuType: .shared, arch: .x86),
        serverType(id: 32, name: "cx32", cores: 4, memory: 8, disk: 80, cpuType: .shared, arch: .x86),
        serverType(id: 42, name: "cx42", cores: 8, memory: 16, disk: 160, cpuType: .shared, arch: .x86),
        serverType(id: 31, name: "cpx31", cores: 4, memory: 8, disk: 160, cpuType: .dedicated, arch: .x86),
        serverType(id: 13, name: "ccx13", cores: 2, memory: 8, disk: 80, cpuType: .dedicated, arch: .x86, deprecated: true),
        serverType(id: 111, name: "cax11", cores: 2, memory: 4, disk: 40, cpuType: .shared, arch: .arm),
        serverType(id: 121, name: "cax21", cores: 4, memory: 8, disk: 80, cpuType: .shared, arch: .arm),
    ]

    static let sshKeys: [SSHKey] = [
        SSHKey(id: 1, name: "personal-mac", fingerprint: "aa:bb:cc:dd", publicKey: "ssh-ed25519 AAAA...", labels: [:], created: Date()),
        SSHKey(id: 2, name: "work-laptop", fingerprint: "11:22:33:44", publicKey: "ssh-ed25519 AAAA...", labels: [:], created: Date()),
    ]

    static let networks: [Network] = [
        Network(
            id: 1, name: "prod-net", ipRange: "10.0.0.0/16",
            subnets: [], routes: [], servers: [],
            protection: NetworkProtection(delete: false), labels: [:], created: Date(),
            exposeRoutesToVswitch: nil
        ),
    ]

    static let firewalls: [Firewall] = [
        Firewall(id: 1, name: "web-fw", labels: [:], created: Date(), rules: [], appliedTo: []),
    ]

    // Every server type priced at nbg1/fsn1/hel1; only the shared x86
    // line-up is also sold at ash/sin, so the "hide unavailable types" rule
    // has something to actually hide in the type-step preview.
    private static func prices(_ monthlyByLocation: [String: String]) -> [ServerTypePrice] {
        monthlyByLocation.map { location, monthly in
            ServerTypePrice(
                location: location,
                hourly: PriceValue(net: hourlyFromMonthly(monthly), gross: hourlyFromMonthly(monthly)),
                monthly: PriceValue(net: monthly, gross: monthly)
            )
        }
    }

    static let pricing = Pricing(
        currency: "EUR",
        vatRate: "19.00",
        serverTypes: [
            PricingServerType(id: 22, name: "cx22", prices: prices(["nbg1": "3.79", "fsn1": "3.79", "hel1": "3.79", "ash": "4.49", "sin": "5.49"])),
            PricingServerType(id: 32, name: "cx32", prices: prices(["nbg1": "6.90", "fsn1": "6.90", "hel1": "6.90", "ash": "7.90", "sin": "9.90"])),
            PricingServerType(id: 42, name: "cx42", prices: prices(["nbg1": "13.10", "fsn1": "13.10", "hel1": "13.10"])),
            PricingServerType(id: 31, name: "cpx31", prices: prices(["nbg1": "12.49", "fsn1": "12.49", "hel1": "12.49"])),
            PricingServerType(id: 13, name: "ccx13", prices: prices(["nbg1": "24.90", "fsn1": "24.90"])),
            PricingServerType(id: 111, name: "cax11", prices: prices(["nbg1": "3.29", "fsn1": "3.29", "hel1": "3.29"])),
            PricingServerType(id: 121, name: "cax21", prices: prices(["nbg1": "5.39", "fsn1": "5.39", "hel1": "5.39"])),
        ],
        primaryIPs: [],
        volumePerGBMonth: PriceValue(net: "0.0440", gross: "0.0440"),
        serverBackupPercentage: "20.00"
    )

    private static func hourlyFromMonthly(_ monthly: String) -> String {
        guard let value = Decimal(string: monthly) else { return "0.0000" }
        let hourly = value / 672 // ~30 day fallback divisor, close enough for preview display
        return NSDecimalNumber(decimal: hourly).stringValue
    }

    private static func image(id: Int, name: String, flavor: String, version: String, arch: Architecture, daysAgo: Int) -> HetznerImage {
        HetznerImage(
            id: id, type: .system, status: .available, name: name,
            description: "\(flavor.capitalized) \(version)",
            imageSize: nil, diskSize: 10,
            created: Date().addingTimeInterval(-Double(daysAgo) * 86_400),
            createdFrom: nil, boundTo: nil,
            osFlavor: flavor, osVersion: version, architecture: arch,
            protection: ImageProtection(delete: false), deprecated: nil, labels: [:]
        )
    }

    private static func serverType(
        id: Int, name: String, cores: Int, memory: Double, disk: Int,
        cpuType: CPUType, arch: Architecture, deprecated: Bool = false
    ) -> ServerType {
        ServerType(
            id: id, name: name, description: name.uppercased(), cores: cores,
            memory: memory, disk: disk, cpuType: cpuType, architecture: arch,
            deprecated: deprecated, prices: []
        )
    }

    /// Fully loaded view model, ready to render any step, with no selections
    /// made yet.
    @MainActor
    static func viewModel(step: CreateServerStep = .location) -> CreateServerViewModel {
        CreateServerViewModel(
            projectID: UUID(),
            step: step,
            catalogState: .loaded,
            locations: locations,
            images: images,
            serverTypes: serverTypes,
            sshKeys: sshKeys,
            networks: networks,
            firewalls: firewalls,
            pricing: pricing
        )
    }

    /// A view model further along: location, image, and type all selected —
    /// useful for the config step and the footer's price preview.
    @MainActor
    static func configuredViewModel() -> CreateServerViewModel {
        CreateServerViewModel(
            projectID: UUID(),
            step: .config,
            catalogState: .loaded,
            locations: locations,
            images: images,
            serverTypes: serverTypes,
            sshKeys: sshKeys,
            networks: networks,
            firewalls: firewalls,
            pricing: pricing,
            selectedLocation: locations[0],
            selectedImage: images[0],
            selectedServerType: serverTypes[0]
        )
    }

    @MainActor
    static func creatingViewModel(progress: Int = 42) -> CreateServerViewModel {
        CreateServerViewModel(
            projectID: UUID(),
            catalogState: .loaded,
            selectedLocation: locations[0],
            selectedImage: images[0],
            selectedServerType: serverTypes[0],
            phase: .creating(progress: progress)
        )
    }

    @MainActor
    static func succeededViewModel(withRootPassword: Bool) -> CreateServerViewModel {
        let server = Server(
            id: 999, name: "brave-otter-04", status: .initializing,
            created: Date(),
            publicNet: PublicNet(ipv4: PublicNetIPv4(ip: "95.216.3.171"), ipv6: nil),
            serverType: serverTypes[0],
            datacenter: Datacenter(id: 1, name: "nbg1-dc3", description: "Nuremberg DC Park 1", location: locations[0]),
            labels: [:], locked: false,
            protection: ServerProtection(delete: false, rebuild: false),
            backupWindow: nil, rescueEnabled: false, primaryDiskSize: 40,
            includedTraffic: nil, outgoingTraffic: nil, ingoingTraffic: nil
        )
        return CreateServerViewModel(
            projectID: UUID(),
            catalogState: .loaded,
            phase: .succeeded(server),
            createdRootPassword: withRootPassword ? "kR7!qP2xL9zT" : nil
        )
    }

    @MainActor
    static func failedViewModel() -> CreateServerViewModel {
        CreateServerViewModel(
            projectID: UUID(),
            catalogState: .loaded,
            selectedLocation: locations[0],
            selectedImage: images[0],
            selectedServerType: serverTypes[0],
            phase: .failed("This location is temporarily out of capacity for the selected server type.")
        )
    }
}
