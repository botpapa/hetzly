import Foundation
import HetznerKit

/// Preview-only mock data for the Dedicated feature. No network access —
/// every preview in this directory renders from these fixtures.
enum DedicatedPreviewFixtures {
    static let server = RobotServer(
        serverIP: "95.216.3.171",
        serverIPv6Net: "2a01:4f9:c012:4a2b::/64",
        serverNumber: 321_654,
        serverName: "dedi-prod-01",
        product: "AX101",
        dc: "FSN1-DC5",
        traffic: "unlimited",
        status: .ready,
        cancelled: false,
        paidUntil: "2026-08-01",
        ip: nil,
        subnet: nil
    )

    static let inProcessServer = RobotServer(
        serverIP: "95.216.9.4",
        serverIPv6Net: nil,
        serverNumber: 321_655,
        serverName: "",
        product: "AX52",
        dc: "NBG1-DC3",
        traffic: "20 TB",
        status: .inProcess,
        cancelled: false,
        paidUntil: "2026-09-15",
        ip: nil,
        subnet: nil
    )

    static let cancelledServer = RobotServer(
        serverIP: "95.216.11.20",
        serverIPv6Net: nil,
        serverNumber: 321_656,
        serverName: "old-box",
        product: "AX41",
        dc: "HEL1-DC2",
        traffic: "5 TB",
        status: .ready,
        cancelled: true,
        paidUntil: "2026-01-01",
        ip: nil,
        subnet: nil
    )

    static let rescueInactive = RobotRescue(
        os: "linux",
        active: false
    )

    static let rescueActive = RobotRescue(
        os: "linux",
        active: true
    )

    static let sshKey = RobotSSHKey(
        name: "MacBook Pro",
        fingerprint: "b7:2f:30:a0:2f:6c:58:6c:21:04:58:61:ba:06:3b:2f",
        data: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIISKa2ipQfmyoJKMWfvNZa5xATcXJTdrbeZDMBGvzimE hetzi"
    )

    static let ip = RobotIP(
        ip: "95.216.3.171",
        serverNumber: 321_654
    )
}
