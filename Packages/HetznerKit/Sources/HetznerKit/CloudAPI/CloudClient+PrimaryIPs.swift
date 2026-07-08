import Foundation

extension CloudClient {
    /// All primary IPs, fully paginated.
    public func listPrimaryIPs() async throws -> [PrimaryIP] {
        let stream: AsyncThrowingStream<[PrimaryIP], Error> = paginated(
            client: client,
            endpoint: Endpoint(path: "/primary_ips"),
            itemsKey: "primary_ips",
            perPage: 50
        )

        var primaryIPs: [PrimaryIP] = []
        for try await page in stream {
            primaryIPs.append(contentsOf: page)
        }
        return primaryIPs
    }

    public func primaryIP(id: Int) async throws -> PrimaryIP {
        let envelope: PrimaryIPEnvelope = try await client.send(Endpoint(path: "/primary_ips/\(id)"))
        return envelope.primaryIP
    }

    /// Creates a primary IP. Supply either `datacenterName` (standalone
    /// creation) or `assigneeID` (created and immediately assigned to a
    /// server) per Hetzner's API contract — supplying `assigneeID` queues an
    /// implicit assignment, surfaced via `CreatedPrimaryIP.action`.
    public func createPrimaryIP(
        name: String,
        type: IPAddressType,
        datacenterName: String? = nil,
        assigneeID: Int? = nil,
        autoDelete: Bool = false,
        labels: [String: String]? = nil
    ) async throws -> CreatedPrimaryIP {
        let request = CreatePrimaryIPRequest(
            name: name,
            type: type,
            datacenter: datacenterName,
            assigneeID: assigneeID,
            autoDelete: autoDelete,
            labels: labels
        )
        let body = try JSONEncoder().encode(request)
        let envelope: CreatePrimaryIPResponseEnvelope = try await client.send(
            Endpoint(method: .post, path: "/primary_ips", body: body)
        )
        return CreatedPrimaryIP(primaryIP: envelope.primaryIP, action: envelope.action)
    }

    /// Hetzner returns `204 No Content` for primary IP deletion.
    public func deletePrimaryIP(id: Int) async throws {
        try await client.sendExpectingNoContent(Endpoint(method: .delete, path: "/primary_ips/\(id)"))
    }

    public func updatePrimaryIP(
        id: Int,
        name: String? = nil,
        autoDelete: Bool? = nil,
        labels: [String: String]? = nil
    ) async throws -> PrimaryIP {
        let body = try JSONEncoder().encode(UpdatePrimaryIPRequest(name: name, autoDelete: autoDelete, labels: labels))
        let envelope: PrimaryIPEnvelope = try await client.send(
            Endpoint(method: .put, path: "/primary_ips/\(id)", body: body)
        )
        return envelope.primaryIP
    }

    public func assignPrimaryIP(id: Int, assigneeID: Int) async throws -> Action {
        let body = try JSONEncoder().encode(AssignPrimaryIPRequest(assigneeID: assigneeID, type: "server"))
        return try await performPrimaryIPAction(id: id, action: "assign", body: body)
    }

    public func unassignPrimaryIP(id: Int) async throws -> Action {
        try await performPrimaryIPAction(id: id, action: "unassign", body: nil)
    }

    public func changePrimaryIPProtection(id: Int, delete: Bool) async throws -> Action {
        let body = try JSONEncoder().encode(ChangePrimaryIPProtectionRequest(delete: delete))
        return try await performPrimaryIPAction(id: id, action: "change_protection", body: body)
    }

    /// Sets (or, with `dnsPtr: nil`, resets to Hetzner's default) the reverse
    /// DNS entry for `ip` — one of the addresses covered by this primary IP.
    public func setPrimaryIPRDNS(id: Int, ip: String, dnsPtr: String?) async throws -> Action {
        let body = try JSONEncoder().encode(ChangeDNSPtrRequest(ip: ip, dnsPtr: dnsPtr))
        return try await performPrimaryIPAction(id: id, action: "change_dns_ptr", body: body)
    }

    private func performPrimaryIPAction(id: Int, action: String, body: Data?) async throws -> Action {
        let envelope: ActionEnvelope = try await client.send(
            Endpoint(method: .post, path: "/primary_ips/\(id)/actions/\(action)", body: body)
        )
        return envelope.action
    }
}

// MARK: - Request bodies

struct CreatePrimaryIPRequest: Encodable, Sendable {
    let name: String
    let type: IPAddressType
    let datacenter: String?
    let assigneeID: Int?
    let autoDelete: Bool
    let labels: [String: String]?

    enum CodingKeys: String, CodingKey {
        case name, type, datacenter
        case assigneeID = "assignee_id"
        case autoDelete = "auto_delete"
        case labels
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(datacenter, forKey: .datacenter)
        try container.encodeIfPresent(assigneeID, forKey: .assigneeID)
        try container.encode(autoDelete, forKey: .autoDelete)
        try container.encodeIfPresent(labels, forKey: .labels)
    }
}

struct UpdatePrimaryIPRequest: Encodable, Sendable {
    let name: String?
    let autoDelete: Bool?
    let labels: [String: String]?

    enum CodingKeys: String, CodingKey {
        case name
        case autoDelete = "auto_delete"
        case labels
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(autoDelete, forKey: .autoDelete)
        try container.encodeIfPresent(labels, forKey: .labels)
    }
}

struct AssignPrimaryIPRequest: Encodable, Sendable {
    let assigneeID: Int
    let type: String

    enum CodingKeys: String, CodingKey {
        case assigneeID = "assignee_id"
        case type
    }
}

struct ChangePrimaryIPProtectionRequest: Encodable, Sendable {
    let delete: Bool
}

struct ChangeDNSPtrRequest: Encodable, Sendable {
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
        // default PTR), so this key is always present — never omitted like
        // the `encodeIfPresent` optionals elsewhere in this file.
        try container.encode(dnsPtr, forKey: .dnsPtr)
    }
}
