import Foundation
import HetznerKit

/// Preview-only mock data for the Firewalls feature. No network access —
/// every `#Preview` in this directory renders from these fixtures.
enum FirewallPreviewFixtures {
    static let now = Date()

    static let webFirewall = Firewall(
        id: 1001,
        name: "web-servers",
        labels: [:],
        created: now.addingTimeInterval(-30 * 24 * 3_600),
        rules: [
            FirewallRule(
                direction: .inbound,
                networkProtocol: .tcp,
                port: "22",
                sourceIPs: ["203.0.113.0/24", "2001:db8::/32"],
                destinationIPs: [],
                description: "SSH"
            ),
            FirewallRule(
                direction: .inbound,
                networkProtocol: .tcp,
                port: "80",
                sourceIPs: ["0.0.0.0/0", "::/0"],
                destinationIPs: [],
                description: "HTTP"
            ),
            FirewallRule(
                direction: .inbound,
                networkProtocol: .icmp,
                port: nil,
                sourceIPs: ["0.0.0.0/0"],
                destinationIPs: [],
                description: "ICMP ping"
            ),
            FirewallRule(
                direction: .outbound,
                networkProtocol: .tcp,
                port: "443",
                sourceIPs: [],
                destinationIPs: ["0.0.0.0/0", "::/0"],
                description: "Outbound HTTPS"
            ),
        ],
        appliedTo: [
            FirewallResource(
                type: .server,
                server: FirewallResourceServerRef(id: 42),
                labelSelector: nil,
                appliedToResources: nil
            ),
            FirewallResource(
                type: .labelSelector,
                server: nil,
                labelSelector: FirewallLabelSelectorRef(selector: "env=prod"),
                appliedToResources: [
                    FirewallAppliedToResource(type: .server, server: FirewallResourceServerRef(id: 43)),
                ]
            ),
        ]
    )

    static let bareFirewall = Firewall(
        id: 1002,
        name: "default-deny",
        labels: [:],
        created: now.addingTimeInterval(-3 * 24 * 3_600),
        rules: [],
        appliedTo: []
    )

    static let servers: [Server] = [
        Server(
            id: 42,
            name: "web-01",
            status: .running,
            created: now.addingTimeInterval(-21 * 24 * 3_600),
            publicNet: PublicNet(ipv4: PublicNetIPv4(ip: "95.216.3.171"), ipv6: nil),
            serverType: ServerType(
                id: 22, name: "cx22", description: "CX22", cores: 2, memory: 4, disk: 40,
                cpuType: .shared, architecture: .x86, deprecated: false, prices: []
            ),
            datacenter: Datacenter(
                id: 3, name: "nbg1-dc3", description: "Nuremberg DC Park 1",
                location: Location(
                    id: 1, name: "nbg1", description: "Nuremberg DC Park 1", country: "DE", city: "Nuremberg",
                    latitude: 49.452102, longitude: 11.076665, networkZone: "eu-central"
                )
            ),
            labels: ["env": "prod"],
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
            name: "web-02",
            status: .running,
            created: now.addingTimeInterval(-10 * 24 * 3_600),
            publicNet: PublicNet(ipv4: PublicNetIPv4(ip: "95.216.3.172"), ipv6: nil),
            serverType: ServerType(
                id: 22, name: "cx22", description: "CX22", cores: 2, memory: 4, disk: 40,
                cpuType: .shared, architecture: .x86, deprecated: false, prices: []
            ),
            datacenter: Datacenter(
                id: 3, name: "nbg1-dc3", description: "Nuremberg DC Park 1",
                location: Location(
                    id: 1, name: "nbg1", description: "Nuremberg DC Park 1", country: "DE", city: "Nuremberg",
                    latitude: 49.452102, longitude: 11.076665, networkZone: "eu-central"
                )
            ),
            labels: ["env": "prod"],
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
}
