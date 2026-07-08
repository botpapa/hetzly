import Foundation
import HetznerKit

/// Preview-only fixture data for the Resources feature. No network access —
/// every `#Preview` in this directory renders from these values.
#if DEBUG
enum ResourcesPreviewFixtures {
    static let now = Date()

    static let location = Location(
        id: 1,
        name: "nbg1",
        description: "Nuremberg DC Park 1",
        country: "DE",
        city: "Nuremberg",
        latitude: 49.452102,
        longitude: 11.076665,
        networkZone: "eu-central"
    )

    static let datacenter = Datacenter(
        id: 3,
        name: "nbg1-dc3",
        description: "Nuremberg DC Park 1",
        location: location
    )

    static let servers: [Server] = [
        Server(
            id: 42,
            name: "hetzi-prod-01",
            status: .running,
            created: now.addingTimeInterval(-21 * 24 * 3_600),
            publicNet: PublicNet(ipv4: PublicNetIPv4(ip: "95.216.3.171"), ipv6: nil),
            serverType: ServerType(id: 22, name: "cx22", description: "CX22", cores: 2, memory: 4, disk: 40, cpuType: .shared, architecture: .x86, deprecated: false, prices: []),
            datacenter: datacenter,
            labels: [:],
            locked: false,
            protection: ServerProtection(delete: false, rebuild: false),
            backupWindow: nil,
            rescueEnabled: false,
            primaryDiskSize: 40,
            includedTraffic: nil,
            outgoingTraffic: nil,
            ingoingTraffic: nil
        ),
        Server(
            id: 43,
            name: "hetzi-staging",
            status: .off,
            created: now.addingTimeInterval(-3 * 24 * 3_600),
            publicNet: PublicNet(ipv4: PublicNetIPv4(ip: "95.216.9.4"), ipv6: nil),
            serverType: ServerType(id: 22, name: "cx22", description: "CX22", cores: 2, memory: 4, disk: 40, cpuType: .shared, architecture: .x86, deprecated: false, prices: []),
            datacenter: datacenter,
            labels: [:],
            locked: false,
            protection: ServerProtection(delete: false, rebuild: false),
            backupWindow: nil,
            rescueEnabled: false,
            primaryDiskSize: 40,
            includedTraffic: nil,
            outgoingTraffic: nil,
            ingoingTraffic: nil
        ),
    ]

    static let volumes: [Volume] = [
        Volume(
            id: 1,
            created: now.addingTimeInterval(-10 * 24 * 3_600),
            name: "data-01",
            server: 42,
            location: location,
            size: 50,
            linuxDevice: "/dev/disk/by-id/scsi-0HC_Volume_1",
            protection: VolumeProtection(delete: false),
            status: .available,
            format: "ext4",
            labels: [:]
        ),
        Volume(
            id: 2,
            created: now.addingTimeInterval(-2 * 24 * 3_600),
            name: "backups",
            server: nil,
            location: location,
            size: 200,
            linuxDevice: "/dev/disk/by-id/scsi-0HC_Volume_2",
            protection: VolumeProtection(delete: true),
            status: .available,
            format: "xfs",
            labels: [:]
        ),
    ]

    static let networks: [Network] = [
        Network(
            id: 1,
            name: "prod-net",
            ipRange: "10.0.0.0/16",
            subnets: [
                NetworkSubnet(type: .cloud, ipRange: "10.0.1.0/24", networkZone: "eu-central", gateway: "10.0.1.1", vswitchID: nil),
            ],
            routes: [
                NetworkRoute(destination: "0.0.0.0/0", gateway: "10.0.1.1"),
            ],
            servers: [42],
            protection: NetworkProtection(delete: false),
            labels: [:],
            created: now.addingTimeInterval(-30 * 24 * 3_600),
            exposeRoutesToVswitch: false
        ),
    ]

    static let primaryIPs: [PrimaryIP] = [
        PrimaryIP(
            id: 1,
            name: "hetzi-prod-01",
            ip: "95.216.3.171",
            type: .ipv4,
            assigneeID: 42,
            assigneeType: "server",
            autoDelete: true,
            blocked: false,
            created: now.addingTimeInterval(-21 * 24 * 3_600),
            datacenter: datacenter,
            dnsPtr: [DNSPtrEntry(ip: "95.216.3.171", dnsPtr: "hetzi-prod-01.example.com")],
            labels: [:],
            protection: DeleteProtection(delete: false)
        ),
        PrimaryIP(
            id: 2,
            name: "spare-ip",
            ip: "95.216.9.99",
            type: .ipv4,
            assigneeID: nil,
            assigneeType: nil,
            autoDelete: false,
            blocked: false,
            created: now.addingTimeInterval(-2 * 24 * 3_600),
            datacenter: datacenter,
            dnsPtr: [],
            labels: [:],
            protection: DeleteProtection(delete: false)
        ),
    ]

    static let floatingIPs: [FloatingIP] = [
        FloatingIP(
            id: 1,
            name: "float-01",
            description: "Failover IP",
            ip: "78.46.1.2",
            type: .ipv4,
            server: 42,
            dnsPtr: [DNSPtrEntry(ip: "78.46.1.2", dnsPtr: nil)],
            homeLocation: location,
            blocked: false,
            protection: DeleteProtection(delete: false),
            labels: [:],
            created: now.addingTimeInterval(-15 * 24 * 3_600)
        ),
    ]

    static let sshKeys: [SSHKey] = [
        SSHKey(
            id: 1,
            name: "MacBook Pro",
            fingerprint: "aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99",
            publicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyMaterialForPreviewOnly andrew@macbook",
            labels: [:],
            created: now.addingTimeInterval(-60 * 24 * 3_600)
        ),
    ]

    static let certificates: [Certificate] = [
        Certificate(
            id: 1,
            name: "example-com",
            labels: [:],
            type: .managed,
            certificate: "-----BEGIN CERTIFICATE-----\nMIIB...\n-----END CERTIFICATE-----",
            created: now.addingTimeInterval(-40 * 24 * 3_600),
            notValidBefore: now.addingTimeInterval(-10 * 24 * 3_600),
            notValidAfter: now.addingTimeInterval(80 * 24 * 3_600),
            domainNames: ["example.com", "www.example.com"],
            fingerprint: "12:34:56:78:9a:bc:de:f0",
            status: CertificateStatus(issuance: .completed, renewal: .completed)
        ),
        Certificate(
            id: 2,
            name: "uploaded-cert",
            labels: [:],
            type: .uploaded,
            certificate: "-----BEGIN CERTIFICATE-----\nMIIB...\n-----END CERTIFICATE-----",
            created: now.addingTimeInterval(-5 * 24 * 3_600),
            notValidBefore: now.addingTimeInterval(-5 * 24 * 3_600),
            notValidAfter: now.addingTimeInterval(360 * 24 * 3_600),
            domainNames: ["upload.example.com"],
            fingerprint: "ab:cd:ef:01:23:45:67:89",
            status: nil
        ),
    ]

    static let placementGroups: [PlacementGroup] = [
        PlacementGroup(
            id: 1,
            name: "prod-spread",
            labels: [:],
            type: .spread,
            servers: [42, 43],
            created: now.addingTimeInterval(-45 * 24 * 3_600)
        ),
    ]

    static let pricing = Pricing(
        currency: "EUR",
        vatRate: "19.00",
        serverTypes: [],
        primaryIPs: [],
        volumePerGBMonth: PriceValue(net: "0.0440", gross: "0.0524"),
        serverBackupPercentage: "20"
    )
}
#endif
