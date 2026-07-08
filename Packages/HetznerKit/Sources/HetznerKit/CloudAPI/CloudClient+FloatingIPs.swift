import Foundation

extension CloudClient {
    /// All floating IPs, fully paginated.
    public func listFloatingIPs() async throws -> [FloatingIP] {
        let stream: AsyncThrowingStream<[FloatingIP], Error> = paginated(
            client: client,
            endpoint: Endpoint(path: "/floating_ips"),
            itemsKey: "floating_ips",
            perPage: 50
        )

        var floatingIPs: [FloatingIP] = []
        for try await page in stream {
            floatingIPs.append(contentsOf: page)
        }
        return floatingIPs
    }

    public func floatingIP(id: Int) async throws -> FloatingIP {
        let envelope: FloatingIPEnvelope = try await client.send(Endpoint(path: "/floating_ips/\(id)"))
        return envelope.floatingIP
    }

    /// Creates a floating IP. Supply either `homeLocationName` (standalone
    /// creation) or `serverID` (created and immediately assigned, which also
    /// determines the home location) per Hetzner's API contract — supplying
    /// `serverID` queues an implicit assignment, surfaced via
    /// `CreatedFloatingIP.action`.
    public func createFloatingIP(
        name: String,
        type: IPAddressType,
        homeLocationName: String? = nil,
        serverID: Int? = nil,
        description: String? = nil,
        labels: [String: String]? = nil
    ) async throws -> CreatedFloatingIP {
        let request = CreateFloatingIPRequest(
            name: name,
            type: type,
            homeLocation: homeLocationName,
            server: serverID,
            description: description,
            labels: labels
        )
        let body = try JSONEncoder().encode(request)
        let envelope: CreateFloatingIPResponseEnvelope = try await client.send(
            Endpoint(method: .post, path: "/floating_ips", body: body)
        )
        return CreatedFloatingIP(floatingIP: envelope.floatingIP, action: envelope.action)
    }

    /// Hetzner returns `204 No Content` for floating IP deletion.
    public func deleteFloatingIP(id: Int) async throws {
        try await client.sendExpectingNoContent(Endpoint(method: .delete, path: "/floating_ips/\(id)"))
    }

    public func updateFloatingIP(
        id: Int,
        name: String? = nil,
        description: String? = nil,
        labels: [String: String]? = nil
    ) async throws -> FloatingIP {
        let body = try JSONEncoder().encode(
            UpdateFloatingIPRequest(name: name, description: description, labels: labels)
        )
        let envelope: FloatingIPEnvelope = try await client.send(
            Endpoint(method: .put, path: "/floating_ips/\(id)", body: body)
        )
        return envelope.floatingIP
    }

    public func assignFloatingIP(id: Int, serverID: Int) async throws -> Action {
        let body = try JSONEncoder().encode(AssignFloatingIPRequest(server: serverID))
        return try await performFloatingIPAction(id: id, action: "assign", body: body)
    }

    public func unassignFloatingIP(id: Int) async throws -> Action {
        try await performFloatingIPAction(id: id, action: "unassign", body: nil)
    }

    public func changeFloatingIPProtection(id: Int, delete: Bool) async throws -> Action {
        let body = try JSONEncoder().encode(ChangeFloatingIPProtectionRequest(delete: delete))
        return try await performFloatingIPAction(id: id, action: "change_protection", body: body)
    }

    /// Sets (or, with `dnsPtr: nil`, resets to Hetzner's default) the reverse
    /// DNS entry for `ip` — one of the addresses covered by this floating IP.
    public func setFloatingIPRDNS(id: Int, ip: String, dnsPtr: String?) async throws -> Action {
        let body = try JSONEncoder().encode(ChangeFloatingIPDNSPtrRequest(ip: ip, dnsPtr: dnsPtr))
        return try await performFloatingIPAction(id: id, action: "change_dns_ptr", body: body)
    }

    private func performFloatingIPAction(id: Int, action: String, body: Data?) async throws -> Action {
        let envelope: ActionEnvelope = try await client.send(
            Endpoint(method: .post, path: "/floating_ips/\(id)/actions/\(action)", body: body)
        )
        return envelope.action
    }
}

// MARK: - Request bodies

struct CreateFloatingIPRequest: Encodable, Sendable {
    let name: String
    let type: IPAddressType
    let homeLocation: String?
    let server: Int?
    let description: String?
    let labels: [String: String]?

    enum CodingKeys: String, CodingKey {
        case name, type
        case homeLocation = "home_location"
        case server, description, labels
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(homeLocation, forKey: .homeLocation)
        try container.encodeIfPresent(server, forKey: .server)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(labels, forKey: .labels)
    }
}

struct UpdateFloatingIPRequest: Encodable, Sendable {
    let name: String?
    let description: String?
    let labels: [String: String]?

    enum CodingKeys: String, CodingKey { case name, description, labels }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(labels, forKey: .labels)
    }
}

struct AssignFloatingIPRequest: Encodable, Sendable {
    let server: Int
}

struct ChangeFloatingIPProtectionRequest: Encodable, Sendable {
    let delete: Bool
}

struct ChangeFloatingIPDNSPtrRequest: Encodable, Sendable {
    let ip: String
    let dnsPtr: String?

    enum CodingKeys: String, CodingKey {
        case ip
        case dnsPtr = "dns_ptr"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ip, forKey: .ip)
        // `dns_ptr: null` is a meaningful request (resets to Hetzner's
        // default PTR), so this key is always present.
        try container.encode(dnsPtr, forKey: .dnsPtr)
    }
}
