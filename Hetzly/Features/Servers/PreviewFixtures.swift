import Foundation
import HetznerKit

/// Preview-only mock data for the Server Detail feature.
///
/// Built directly against the model shapes described in `CONTRACTS.md`
/// (Worker A's `CloudAPI` module lands concurrently with this feature, so
/// the exact memberwise-initializer labels/order here are a best effort —
/// expect small touch-ups once `Packages/HetznerKit/Sources/HetznerKit/CloudAPI`
/// is populated for real). No network access; every preview in this
/// directory renders from this fixture.
enum PreviewFixtures {
    static let now = Date()

    static let server = Server(
        id: 42,
        name: "hetzi-prod-01",
        status: .running,
        created: now.addingTimeInterval(-21 * 24 * 3_600),
        publicNet: PublicNet(
            ipv4: PublicNetIPv4(ip: "95.216.3.171"),
            ipv6: PublicNetIPv6(ip: "2a01:4f9:c012:4a2b::/64")
        ),
        serverType: ServerType(
            id: 22,
            name: "cx22",
            description: "CX22",
            cores: 2,
            memory: 4,
            disk: 40,
            cpuType: .shared,
            architecture: .x86,
            deprecated: false,
            prices: []
        ),
        datacenter: Datacenter(
            id: 3,
            name: "nbg1-dc3",
            description: "Nuremberg DC Park 1",
            location: Location(
                id: 1,
                name: "nbg1",
                description: "Nuremberg DC Park 1",
                country: "DE",
                city: "Nuremberg",
                latitude: 49.452102,
                longitude: 11.076665,
                networkZone: "eu-central"
            )
        ),
        labels: ["env": "prod"],
        locked: false,
        protection: ServerProtection(delete: false, rebuild: false),
        backupWindow: "22-02",
        rescueEnabled: false,
        primaryDiskSize: 40,
        includedTraffic: 21_990_232_555_520,
        outgoingTraffic: 128_849_018_880,
        ingoingTraffic: 42_949_672_960
    )

    static let offServer = Server(
        id: 43,
        name: "hetzi-staging",
        status: .off,
        created: now.addingTimeInterval(-3 * 24 * 3_600),
        publicNet: PublicNet(
            ipv4: PublicNetIPv4(ip: "95.216.9.4"),
            ipv6: nil
        ),
        serverType: ServerType(
            id: 22,
            name: "cx22",
            description: "CX22",
            cores: 2,
            memory: 4,
            disk: 40,
            cpuType: .shared,
            architecture: .x86,
            deprecated: false,
            prices: []
        ),
        datacenter: Datacenter(
            id: 3,
            name: "nbg1-dc3",
            description: "Nuremberg DC Park 1",
            location: Location(
                id: 1,
                name: "nbg1",
                description: "Nuremberg DC Park 1",
                country: "DE",
                city: "Nuremberg",
                latitude: 49.452102,
                longitude: 11.076665,
                networkZone: "eu-central"
            )
        ),
        labels: [:],
        locked: false,
        protection: ServerProtection(delete: false, rebuild: false),
        backupWindow: nil,
        rescueEnabled: false,
        primaryDiskSize: 40,
        includedTraffic: 21_990_232_555_520,
        outgoingTraffic: 0,
        ingoingTraffic: 0
    )

    static let metrics: ServerMetrics = {
        let step: TimeInterval = 60
        let start = now.addingTimeInterval(-3_600)
        return ServerMetrics(
            start: start,
            end: now,
            step: step,
            series: [
                MetricsSeries(name: "cpu", points: wave(start: start, step: step, base: 22, amplitude: 18)),
                MetricsSeries(name: "network.0.bandwidth.in", points: wave(start: start, step: step, base: 2_400_000, amplitude: 1_800_000)),
                MetricsSeries(name: "network.0.bandwidth.out", points: wave(start: start, step: step, base: 900_000, amplitude: 600_000)),
                MetricsSeries(name: "disk.0.bandwidth.read", points: wave(start: start, step: step, base: 500_000, amplitude: 400_000)),
                MetricsSeries(name: "disk.0.bandwidth.write", points: wave(start: start, step: step, base: 1_200_000, amplitude: 900_000)),
            ]
        )
    }()

    static let snapshot = Image(
        id: 9_001,
        type: .snapshot,
        status: .available,
        name: nil,
        description: "pre-upgrade checkpoint",
        imageSize: 12.4,
        diskSize: 40,
        created: now.addingTimeInterval(-5 * 24 * 3_600),
        createdFrom: ImageCreator(id: 42, name: "hetzi-prod-01"),
        boundTo: nil,
        osFlavor: "ubuntu",
        osVersion: "24.04",
        architecture: .x86,
        protection: ImageProtection(delete: false),
        deprecated: nil,
        labels: [:]
    )

    static let systemImage = Image(
        id: 114_690_387,
        type: .system,
        status: .available,
        name: "ubuntu-24.04",
        description: "Ubuntu 24.04",
        imageSize: nil,
        diskSize: 5,
        created: now.addingTimeInterval(-300 * 24 * 3_600),
        createdFrom: nil,
        boundTo: nil,
        osFlavor: "ubuntu",
        osVersion: "24.04",
        architecture: .x86,
        protection: ImageProtection(delete: false),
        deprecated: nil,
        labels: [:]
    )

    static let debianImage = Image(
        id: 114_690_388,
        type: .system,
        status: .available,
        name: "debian-12",
        description: "Debian 12",
        imageSize: nil,
        diskSize: 5,
        created: now.addingTimeInterval(-400 * 24 * 3_600),
        createdFrom: nil,
        boundTo: nil,
        osFlavor: "debian",
        osVersion: "12",
        architecture: .x86,
        protection: ImageProtection(delete: false),
        deprecated: nil,
        labels: [:]
    )

    static let iso = ISO(
        id: 12_345,
        name: "debian-12.5.0-amd64-netinst.iso",
        description: "Debian 12.5 (netinst)",
        type: .public,
        architecture: .x86,
        deprecation: nil
    )

    static let sshKey = SSHKey(
        id: 77,
        name: "MacBook Pro",
        fingerprint: "b7:2f:30:a0:2f:6c:58:6c:21:04:58:61:ba:06:3b:2f",
        publicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIISKa2ipQfmyoJKMWfvNZa5xATcXJTdrbeZDMBGvzimE hetzi",
        labels: [:],
        created: now.addingTimeInterval(-60 * 24 * 3_600)
    )

    static let biggerServerType = ServerType(
        id: 23,
        name: "cx32",
        description: "CX32",
        cores: 4,
        memory: 8,
        disk: 80,
        cpuType: .shared,
        architecture: .x86,
        deprecated: false,
        prices: [
            ServerTypePrice(
                location: "nbg1",
                hourly: PriceValue(net: "0.0113", gross: "0.0134"),
                monthly: PriceValue(net: "6.8", gross: "8.09")
            )
        ]
    )

    static let smallerServerType = ServerType(
        id: 21,
        name: "cx12",
        description: "CX12",
        cores: 1,
        memory: 2,
        disk: 20,
        cpuType: .shared,
        architecture: .x86,
        deprecated: false,
        prices: [
            ServerTypePrice(
                location: "nbg1",
                hourly: PriceValue(net: "0.0052", gross: "0.0062"),
                monthly: PriceValue(net: "3.2", gross: "3.81")
            )
        ]
    )

    private static func wave(
        start: Date, step: TimeInterval, base: Double, amplitude: Double, count: Int = 60
    ) -> [(timestamp: Date, value: Double)] {
        (0..<count).map { index in
            let angle = Double(index) / Double(count) * 4 * .pi
            let value = max(0, base + amplitude * sin(angle) + Double.random(in: -amplitude * 0.15...amplitude * 0.15))
            return (timestamp: start.addingTimeInterval(Double(index) * step), value: value)
        }
    }
}
