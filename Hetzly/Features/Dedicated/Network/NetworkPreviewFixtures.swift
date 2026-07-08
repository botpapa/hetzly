import Foundation
import HetznerKit

/// Preview-only mock data for the vSwitch + Failover IP UI. No network
/// access — every preview in this directory renders from these fixtures.
enum NetworkPreviewFixtures {
    static let vSwitch = RobotVSwitch(
        id: 4321,
        name: "Private Backend",
        vlan: 4001,
        cancelled: false,
        servers: [
            RobotVSwitchServer(serverNumber: 321_654, serverIP: "95.216.3.171", status: .ready),
            RobotVSwitchServer(serverNumber: 321_655, serverIP: "95.216.9.4", status: .inProcess),
        ],
        subnets: [
            RobotVSwitchSubnet(ip: "10.0.0.0", mask: "24"),
        ],
        cloudNetworks: [
            RobotCloudNetwork(id: 9876, ip: "10.1.0.0", mask: "16"),
        ]
    )

    static let cancelledVSwitch = RobotVSwitch(
        id: 4322,
        name: "Legacy Bridge",
        vlan: 4050,
        cancelled: true,
        servers: [
            RobotVSwitchServer(serverNumber: 321_656, serverIP: "95.216.11.20", status: .failed),
        ],
        subnets: [],
        cloudNetworks: []
    )

    static let emptyVSwitch = RobotVSwitch(
        id: 4323,
        name: "Fresh vSwitch",
        vlan: 4010,
        cancelled: false,
        servers: [],
        subnets: [],
        cloudNetworks: []
    )

    static let failoverIP = RobotFailover(
        ip: "138.201.22.100",
        netmask: "255.255.255.255",
        serverNumber: 321_654,
        serverIP: "95.216.3.171",
        activeServerIP: "95.216.3.171"
    )

    static let reroutedFailoverIP = RobotFailover(
        ip: "138.201.22.101",
        netmask: "255.255.255.255",
        serverNumber: 321_654,
        serverIP: "95.216.3.171",
        activeServerIP: "95.216.9.4"
    )
}
