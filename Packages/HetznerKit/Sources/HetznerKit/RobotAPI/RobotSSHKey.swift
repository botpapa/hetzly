import Foundation

/// An SSH public key registered on the Robot account (distinct from Cloud's
/// `SSHKey` — separate registry, separate API), from `GET /key`.
public struct RobotSSHKey: Codable, Sendable, Identifiable, Equatable {
    public var id: String { fingerprint }

    public let name: String
    public let fingerprint: String
    public let type: String?
    public let size: Int?
    public let data: String?

    enum CodingKeys: String, CodingKey { case name, fingerprint, type, size, data }

    public init(name: String, fingerprint: String, type: String? = nil, size: Int? = nil, data: String? = nil) {
        self.name = name
        self.fingerprint = fingerprint
        self.type = type
        self.size = size
        self.data = data
    }
}
