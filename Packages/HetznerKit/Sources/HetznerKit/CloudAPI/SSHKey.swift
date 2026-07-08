import Foundation

/// A Hetzner Cloud SSH key registered on the project, usable when creating
/// servers or enabling rescue mode.
public struct SSHKey: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let fingerprint: String
    public let publicKey: String
    public let labels: [String: String]
    public let created: Date

    enum CodingKeys: String, CodingKey {
        case id, name, fingerprint
        case publicKey = "public_key"
        case labels, created
    }

    public init(
        id: Int,
        name: String,
        fingerprint: String,
        publicKey: String,
        labels: [String: String],
        created: Date
    ) {
        self.id = id
        self.name = name
        self.fingerprint = fingerprint
        self.publicKey = publicKey
        self.labels = labels
        self.created = created
    }
}

/// Wire envelope for `GET/POST/PUT /ssh_keys/{id}` → `{"ssh_key": {...}}`.
struct SSHKeyEnvelope: Decodable, Sendable {
    let sshKey: SSHKey

    enum CodingKeys: String, CodingKey {
        case sshKey = "ssh_key"
    }
}
