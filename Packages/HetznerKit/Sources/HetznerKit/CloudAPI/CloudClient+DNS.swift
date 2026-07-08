import Foundation

extension CloudClient {
    /// All DNS zones, fully paginated.
    public func listZones() async throws -> [DNSZone] {
        let stream: AsyncThrowingStream<[DNSZone], Error> = paginated(
            client: client,
            endpoint: Endpoint(path: "/zones"),
            itemsKey: "zones",
            perPage: 50
        )

        var zones: [DNSZone] = []
        for try await page in stream {
            zones.append(contentsOf: page)
        }
        return zones
    }

    public func zone(id: Int) async throws -> DNSZone {
        let envelope: DNSZoneEnvelope = try await client.send(Endpoint(path: "/zones/\(id)"))
        return envelope.zone
    }

    /// Creates a primary DNS zone. Hetzner returns `201 Created` with the
    /// new zone plus a `create_zone` action.
    public func createZone(name: String, ttl: Int? = nil, labels: [String: String]? = nil) async throws -> CreatedDNSZone {
        let request = CreateZoneRequest(name: name, mode: "primary", ttl: ttl, labels: labels)
        let body = try JSONEncoder().encode(request)
        let envelope: CreateDNSZoneResponseEnvelope = try await client.send(
            Endpoint(method: .post, path: "/zones", body: body)
        )
        return CreatedDNSZone(zone: envelope.zone, action: envelope.action)
    }

    /// Hetzner returns `204 No Content` for zone deletion.
    public func deleteZone(id: Int) async throws {
        try await client.sendExpectingNoContent(Endpoint(method: .delete, path: "/zones/\(id)"))
    }

    /// All record sets in a zone, fully paginated.
    public func listRecordSets(zoneID: Int) async throws -> [DNSRecordSet] {
        let stream: AsyncThrowingStream<[DNSRecordSet], Error> = paginated(
            client: client,
            endpoint: Endpoint(path: "/zones/\(zoneID)/rrsets"),
            itemsKey: "rrsets",
            perPage: 50
        )

        var rrsets: [DNSRecordSet] = []
        for try await page in stream {
            rrsets.append(contentsOf: page)
        }
        return rrsets
    }

    public func recordSet(zoneID: Int, name: String, type: DNSRecordType) async throws -> DNSRecordSet {
        let envelope: DNSRecordSetEnvelope = try await client.send(
            Endpoint(path: "/zones/\(zoneID)/rrsets/\(Self.pathComponent(name))/\(type.rawValue)")
        )
        return envelope.rrset
    }

    /// Creates a record set. Hetzner returns `201 Created` with the new
    /// rrset (synchronous — no action).
    public func createRecordSet(
        zoneID: Int,
        name: String,
        type: DNSRecordType,
        records: [DNSRecordValue],
        ttl: Int? = nil,
        labels: [String: String]? = nil
    ) async throws -> DNSRecordSet {
        let request = CreateRecordSetRequest(name: name, type: type.rawValue, ttl: ttl, labels: labels, records: records)
        let body = try JSONEncoder().encode(request)
        let envelope: DNSRecordSetEnvelope = try await client.send(
            Endpoint(method: .post, path: "/zones/\(zoneID)/rrsets", body: body)
        )
        return envelope.rrset
    }

    /// Replaces a record set's records via `PUT /zones/{zoneID}/rrsets/{name}/{type}`.
    public func updateRecordSet(
        zoneID: Int,
        name: String,
        type: DNSRecordType,
        records: [DNSRecordValue],
        ttl: Int? = nil,
        labels: [String: String]? = nil
    ) async throws -> DNSRecordSet {
        let request = UpdateRecordSetRequest(ttl: ttl, labels: labels, records: records)
        let body = try JSONEncoder().encode(request)
        let envelope: DNSRecordSetEnvelope = try await client.send(
            Endpoint(method: .put, path: "/zones/\(zoneID)/rrsets/\(Self.pathComponent(name))/\(type.rawValue)", body: body)
        )
        return envelope.rrset
    }

    /// Hetzner returns `204 No Content` for record set deletion.
    public func deleteRecordSet(zoneID: Int, name: String, type: DNSRecordType) async throws {
        try await client.sendExpectingNoContent(
            Endpoint(method: .delete, path: "/zones/\(zoneID)/rrsets/\(Self.pathComponent(name))/\(type.rawValue)")
        )
    }

    /// Percent-encodes an rrset name for use as a URL path component (record
    /// names can contain characters like `*` for wildcards).
    private static func pathComponent(_ name: String) -> String {
        name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
    }
}

// MARK: - Request bodies

struct CreateZoneRequest: Encodable, Sendable {
    let name: String
    let mode: String
    let ttl: Int?
    let labels: [String: String]?

    enum CodingKeys: String, CodingKey { case name, mode, ttl, labels }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(mode, forKey: .mode)
        try container.encodeIfPresent(ttl, forKey: .ttl)
        try container.encodeIfPresent(labels, forKey: .labels)
    }
}

struct CreateRecordSetRequest: Encodable, Sendable {
    let name: String
    let type: String
    let ttl: Int?
    let labels: [String: String]?
    let records: [DNSRecordValue]?

    enum CodingKeys: String, CodingKey { case name, type, ttl, labels, records }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(ttl, forKey: .ttl)
        try container.encodeIfPresent(labels, forKey: .labels)
        try container.encodeIfPresent(records, forKey: .records)
    }
}

struct UpdateRecordSetRequest: Encodable, Sendable {
    let ttl: Int?
    let labels: [String: String]?
    let records: [DNSRecordValue]?

    enum CodingKeys: String, CodingKey { case ttl, labels, records }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(ttl, forKey: .ttl)
        try container.encodeIfPresent(labels, forKey: .labels)
        try container.encodeIfPresent(records, forKey: .records)
    }
}
