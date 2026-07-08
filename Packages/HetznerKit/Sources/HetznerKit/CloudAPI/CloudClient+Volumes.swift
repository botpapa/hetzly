import Foundation

extension CloudClient {
    /// All volumes, fully paginated.
    public func listVolumes() async throws -> [Volume] {
        let stream: AsyncThrowingStream<[Volume], Error> = paginated(
            client: client,
            endpoint: Endpoint(path: "/volumes"),
            itemsKey: "volumes",
            perPage: 50
        )

        var volumes: [Volume] = []
        for try await page in stream {
            volumes.append(contentsOf: page)
        }
        return volumes
    }

    public func volume(id: Int) async throws -> Volume {
        let envelope: VolumeEnvelope = try await client.send(Endpoint(path: "/volumes/\(id)"))
        return envelope.volume
    }

    /// Creates a volume. Exactly one of `locationName` or `serverID` should be
    /// supplied per Hetzner's API contract — supplying `serverID` queues an
    /// `attach_volume` action, surfaced via `CreatedVolume.nextActions`.
    public func createVolume(
        name: String,
        size: Int,
        locationName: String? = nil,
        serverID: Int? = nil,
        automount: Bool? = nil,
        format: String? = nil
    ) async throws -> CreatedVolume {
        let request = CreateVolumeRequest(
            name: name,
            size: size,
            location: locationName,
            server: serverID,
            automount: automount,
            format: format
        )
        let body = try JSONEncoder().encode(request)
        let envelope: CreateVolumeResponseEnvelope = try await client.send(
            Endpoint(method: .post, path: "/volumes", body: body)
        )
        return CreatedVolume(volume: envelope.volume, action: envelope.action, nextActions: envelope.nextActions ?? [])
    }

    /// Deletes a volume. Hetzner returns `204 No Content` (unlike server
    /// deletion, which returns an action).
    public func deleteVolume(id: Int) async throws {
        try await client.sendExpectingNoContent(Endpoint(method: .delete, path: "/volumes/\(id)"))
    }

    public func resizeVolume(id: Int, size: Int) async throws -> Action {
        let body = try JSONEncoder().encode(ResizeVolumeRequest(size: size))
        return try await performVolumeAction(id: id, action: "resize", body: body)
    }

    public func attachVolume(id: Int, serverID: Int, automount: Bool? = nil) async throws -> Action {
        let body = try JSONEncoder().encode(AttachVolumeRequest(server: serverID, automount: automount))
        return try await performVolumeAction(id: id, action: "attach", body: body)
    }

    public func detachVolume(id: Int) async throws -> Action {
        try await performVolumeAction(id: id, action: "detach", body: nil)
    }

    public func changeVolumeProtection(id: Int, delete: Bool) async throws -> Action {
        let body = try JSONEncoder().encode(ChangeProtectionRequest(delete: delete))
        return try await performVolumeAction(id: id, action: "change_protection", body: body)
    }

    /// Renames and/or relabels a volume via `PUT /volumes/{id}`.
    public func updateVolume(id: Int, name: String? = nil, labels: [String: String]? = nil) async throws -> Volume {
        let request = UpdateVolumeRequest(name: name, labels: labels)
        let body = try JSONEncoder().encode(request)
        let envelope: VolumeEnvelope = try await client.send(
            Endpoint(method: .put, path: "/volumes/\(id)", body: body)
        )
        return envelope.volume
    }

    public func updateVolumeLabels(id: Int, labels: [String: String]) async throws -> Volume {
        try await updateVolume(id: id, labels: labels)
    }

    private func performVolumeAction(id: Int, action: String, body: Data?) async throws -> Action {
        let envelope: ActionEnvelope = try await client.send(
            Endpoint(method: .post, path: "/volumes/\(id)/actions/\(action)", body: body)
        )
        return envelope.action
    }
}

// MARK: - Request bodies

struct CreateVolumeRequest: Encodable, Sendable {
    let name: String
    let size: Int
    let location: String?
    let server: Int?
    let automount: Bool?
    let format: String?

    enum CodingKeys: String, CodingKey {
        case name, size, location, server, automount, format
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(size, forKey: .size)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(server, forKey: .server)
        try container.encodeIfPresent(automount, forKey: .automount)
        try container.encodeIfPresent(format, forKey: .format)
    }
}

struct ResizeVolumeRequest: Encodable, Sendable {
    let size: Int
    enum CodingKeys: String, CodingKey { case size }
}

struct AttachVolumeRequest: Encodable, Sendable {
    let server: Int
    let automount: Bool?

    enum CodingKeys: String, CodingKey { case server, automount }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(server, forKey: .server)
        try container.encodeIfPresent(automount, forKey: .automount)
    }
}

struct ChangeProtectionRequest: Encodable, Sendable {
    let delete: Bool
    enum CodingKeys: String, CodingKey { case delete }
}

struct UpdateVolumeRequest: Encodable, Sendable {
    let name: String?
    let labels: [String: String]?

    enum CodingKeys: String, CodingKey { case name, labels }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(labels, forKey: .labels)
    }
}
