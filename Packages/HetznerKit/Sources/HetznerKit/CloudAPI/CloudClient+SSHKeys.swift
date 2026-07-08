import Foundation

extension CloudClient {
    /// All SSH keys, fully paginated.
    public func listSSHKeys() async throws -> [SSHKey] {
        let stream: AsyncThrowingStream<[SSHKey], Error> = paginated(
            client: client,
            endpoint: Endpoint(path: "/ssh_keys"),
            itemsKey: "ssh_keys",
            perPage: 50
        )

        var keys: [SSHKey] = []
        for try await page in stream {
            keys.append(contentsOf: page)
        }
        return keys
    }

    public func sshKey(id: Int) async throws -> SSHKey {
        let envelope: SSHKeyEnvelope = try await client.send(Endpoint(path: "/ssh_keys/\(id)"))
        return envelope.sshKey
    }

    /// Registers a new SSH public key. Hetzner returns `201 Created` with the
    /// full key object (no action — registration is synchronous).
    public func createSSHKey(
        name: String,
        publicKey: String,
        labels: [String: String]? = nil
    ) async throws -> SSHKey {
        let request = CreateSSHKeyRequest(name: name, publicKey: publicKey, labels: labels)
        let body = try JSONEncoder().encode(request)
        let envelope: SSHKeyEnvelope = try await client.send(Endpoint(method: .post, path: "/ssh_keys", body: body))
        return envelope.sshKey
    }

    /// Renames and/or relabels an SSH key via `PUT /ssh_keys/{id}`.
    public func updateSSHKey(
        id: Int,
        name: String? = nil,
        labels: [String: String]? = nil
    ) async throws -> SSHKey {
        let request = UpdateSSHKeyRequest(name: name, labels: labels)
        let body = try JSONEncoder().encode(request)
        let envelope: SSHKeyEnvelope = try await client.send(
            Endpoint(method: .put, path: "/ssh_keys/\(id)", body: body)
        )
        return envelope.sshKey
    }

    /// Hetzner returns `204 No Content` for SSH key deletion.
    public func deleteSSHKey(id: Int) async throws {
        try await client.sendExpectingNoContent(Endpoint(method: .delete, path: "/ssh_keys/\(id)"))
    }
}

// MARK: - Request bodies

struct CreateSSHKeyRequest: Encodable, Sendable {
    let name: String
    let publicKey: String
    let labels: [String: String]?

    enum CodingKeys: String, CodingKey {
        case name
        case publicKey = "public_key"
        case labels
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(publicKey, forKey: .publicKey)
        try container.encodeIfPresent(labels, forKey: .labels)
    }
}

struct UpdateSSHKeyRequest: Encodable, Sendable {
    let name: String?
    let labels: [String: String]?

    enum CodingKeys: String, CodingKey { case name, labels }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(labels, forKey: .labels)
    }
}
