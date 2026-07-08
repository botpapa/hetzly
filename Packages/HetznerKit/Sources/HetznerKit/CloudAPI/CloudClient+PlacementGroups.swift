import Foundation

extension CloudClient {
    /// All placement groups, fully paginated.
    public func listPlacementGroups() async throws -> [PlacementGroup] {
        let stream: AsyncThrowingStream<[PlacementGroup], Error> = paginated(
            client: client,
            endpoint: Endpoint(path: "/placement_groups"),
            itemsKey: "placement_groups",
            perPage: 50
        )

        var groups: [PlacementGroup] = []
        for try await page in stream {
            groups.append(contentsOf: page)
        }
        return groups
    }

    public func placementGroup(id: Int) async throws -> PlacementGroup {
        let envelope: PlacementGroupEnvelope = try await client.send(Endpoint(path: "/placement_groups/\(id)"))
        return envelope.placementGroup
    }

    public func createPlacementGroup(
        name: String,
        type: PlacementGroupType,
        labels: [String: String]? = nil
    ) async throws -> PlacementGroup {
        let request = CreatePlacementGroupRequest(name: name, type: type.rawValue, labels: labels)
        let body = try JSONEncoder().encode(request)
        let envelope: PlacementGroupEnvelope = try await client.send(
            Endpoint(method: .post, path: "/placement_groups", body: body)
        )
        return envelope.placementGroup
    }

    /// Hetzner returns `204 No Content` for placement group deletion.
    public func deletePlacementGroup(id: Int) async throws {
        try await client.sendExpectingNoContent(Endpoint(method: .delete, path: "/placement_groups/\(id)"))
    }
}

struct CreatePlacementGroupRequest: Encodable, Sendable {
    let name: String
    let type: String
    let labels: [String: String]?

    enum CodingKeys: String, CodingKey { case name, type, labels }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(labels, forKey: .labels)
    }
}
