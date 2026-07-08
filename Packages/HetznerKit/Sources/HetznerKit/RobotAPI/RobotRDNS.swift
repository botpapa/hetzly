import Foundation

/// A reverse DNS (PTR) entry for a single IP, from
/// `GET/POST/PUT /rdns/{ip}`.
public struct RobotRDNS: Codable, Sendable, Identifiable, Equatable {
    public var id: String { ip }

    public let ip: String
    public let ptr: String

    enum CodingKeys: String, CodingKey { case ip, ptr }

    public init(ip: String, ptr: String) {
        self.ip = ip
        self.ptr = ptr
    }
}
