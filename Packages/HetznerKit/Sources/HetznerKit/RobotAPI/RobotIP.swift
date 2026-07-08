import Foundation

/// A single (non-subnet) IP address assigned to a Robot account, from
/// `GET /ip`.
public struct RobotIP: Codable, Sendable, Identifiable, Equatable {
    public var id: String { ip }

    public let ip: String
    public let serverNumber: Int?
    public let locked: Bool?
    public let trafficWarnings: Bool?

    enum CodingKeys: String, CodingKey {
        case ip
        case serverNumber = "server_number"
        case locked
        case trafficWarnings = "traffic_warnings"
    }

    public init(ip: String, serverNumber: Int?, locked: Bool? = nil, trafficWarnings: Bool? = nil) {
        self.ip = ip
        self.serverNumber = serverNumber
        self.locked = locked
        self.trafficWarnings = trafficWarnings
    }
}

/// A routed subnet assigned to a Robot account, from `GET /subnet`.
public struct RobotSubnet: Codable, Sendable, Identifiable, Equatable {
    public var id: String { ip }

    public let ip: String
    public let mask: String
    public let serverNumber: Int?
    public let gateway: String?

    enum CodingKeys: String, CodingKey {
        case ip, mask
        case serverNumber = "server_number"
        case gateway
    }

    public init(ip: String, mask: String, serverNumber: Int?, gateway: String? = nil) {
        self.ip = ip
        self.mask = mask
        self.serverNumber = serverNumber
        self.gateway = gateway
    }
}
