import Foundation

/// A Robot failover IP address (or IPv6 net) and which server it's
/// currently routed to, from `GET /failover` (list) and
/// `GET /failover/{ip}` (single). Unlike vSwitch, failover responses use
/// Robot's usual `{"failover": {...}}` wrapper envelope — see
/// `RobotClient+Failover.swift`.
public struct RobotFailover: Codable, Sendable, Identifiable, Equatable {
    public var id: String { ip }

    /// The failover IP address (or net) itself — this never changes.
    public let ip: String
    public let netmask: String
    /// The server this failover IP is permanently assigned to (its
    /// billing owner) — distinct from `activeServerIP`, which is whichever
    /// server traffic is *currently* routed to and can be switched freely
    /// among the account's authorized servers.
    public let serverNumber: Int
    public let serverIP: String
    public let serverIPv6Net: String?
    /// Currently active routing target's main IP. `nil` once
    /// `RobotClient.deleteFailoverRouting` disables routing.
    public let activeServerIP: String?

    enum CodingKeys: String, CodingKey {
        case ip, netmask
        case serverNumber = "server_number"
        case serverIP = "server_ip"
        case serverIPv6Net = "server_ipv6_net"
        case activeServerIP = "active_server_ip"
    }

    public init(
        ip: String,
        netmask: String,
        serverNumber: Int,
        serverIP: String,
        serverIPv6Net: String? = nil,
        activeServerIP: String? = nil
    ) {
        self.ip = ip
        self.netmask = netmask
        self.serverNumber = serverNumber
        self.serverIP = serverIP
        self.serverIPv6Net = serverIPv6Net
        self.activeServerIP = activeServerIP
    }
}
