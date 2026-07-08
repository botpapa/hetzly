import Foundation

extension CloudClient {
    /// All private networks, fully paginated.
    public func listNetworks() async throws -> [Network] {
        let stream: AsyncThrowingStream<[Network], Error> = paginated(
            client: client,
            endpoint: Endpoint(path: "/networks"),
            itemsKey: "networks",
            perPage: 50
        )

        var networks: [Network] = []
        for try await page in stream {
            networks.append(contentsOf: page)
        }
        return networks
    }

    public func network(id: Int) async throws -> Network {
        let envelope: NetworkEnvelope = try await client.send(Endpoint(path: "/networks/\(id)"))
        return envelope.network
    }

    public func createNetwork(
        name: String,
        ipRange: String,
        subnets: [NetworkSubnetSpec] = [],
        labels: [String: String]? = nil
    ) async throws -> Network {
        let request = CreateNetworkRequest(
            name: name,
            ipRange: ipRange,
            subnets: subnets.map {
                CreateNetworkRequest.SubnetPayload(type: $0.type.rawValue, ipRange: $0.ipRange, networkZone: $0.networkZone)
            },
            labels: labels
        )
        let body = try JSONEncoder().encode(request)
        let envelope: NetworkEnvelope = try await client.send(Endpoint(method: .post, path: "/networks", body: body))
        return envelope.network
    }

    /// Hetzner returns `204 No Content` for network deletion.
    public func deleteNetwork(id: Int) async throws {
        try await client.sendExpectingNoContent(Endpoint(method: .delete, path: "/networks/\(id)"))
    }

    public func updateNetwork(
        id: Int,
        name: String? = nil,
        labels: [String: String]? = nil,
        exposeRoutesToVswitch: Bool? = nil
    ) async throws -> Network {
        let request = UpdateNetworkRequest(name: name, labels: labels, exposeRoutesToVswitch: exposeRoutesToVswitch)
        let body = try JSONEncoder().encode(request)
        let envelope: NetworkEnvelope = try await client.send(Endpoint(method: .put, path: "/networks/\(id)", body: body))
        return envelope.network
    }

    public func addSubnet(networkID: Int, type: NetworkSubnetType, ipRange: String?, networkZone: String) async throws -> Action {
        let body = try JSONEncoder().encode(AddSubnetRequest(type: type.rawValue, ipRange: ipRange, networkZone: networkZone))
        return try await performNetworkAction(networkID: networkID, action: "add_subnet", body: body)
    }

    public func deleteSubnet(networkID: Int, ipRange: String) async throws -> Action {
        let body = try JSONEncoder().encode(DeleteSubnetRequest(ipRange: ipRange))
        return try await performNetworkAction(networkID: networkID, action: "delete_subnet", body: body)
    }

    public func addRoute(networkID: Int, destination: String, gateway: String) async throws -> Action {
        let body = try JSONEncoder().encode(RoutePayloadRequest(destination: destination, gateway: gateway))
        return try await performNetworkAction(networkID: networkID, action: "add_route", body: body)
    }

    public func deleteRoute(networkID: Int, destination: String, gateway: String) async throws -> Action {
        let body = try JSONEncoder().encode(RoutePayloadRequest(destination: destination, gateway: gateway))
        return try await performNetworkAction(networkID: networkID, action: "delete_route", body: body)
    }

    public func changeNetworkProtection(id: Int, delete: Bool) async throws -> Action {
        let body = try JSONEncoder().encode(ChangeProtectionRequest(delete: delete))
        return try await performNetworkAction(networkID: id, action: "change_protection", body: body)
    }

    /// Attaches a server to a network. `ip` requests a specific private IP;
    /// omit to let Hetzner pick one from the subnet automatically.
    public func attachServerToNetwork(
        serverID: Int,
        networkID: Int,
        ip: String? = nil,
        aliasIPs: [String]? = nil
    ) async throws -> Action {
        let body = try JSONEncoder().encode(
            AttachToNetworkRequest(network: networkID, ip: ip, aliasIPs: aliasIPs)
        )
        let envelope: ActionEnvelope = try await client.send(
            Endpoint(method: .post, path: "/servers/\(serverID)/actions/attach_to_network", body: body)
        )
        return envelope.action
    }

    public func detachServerFromNetwork(serverID: Int, networkID: Int) async throws -> Action {
        let body = try JSONEncoder().encode(DetachFromNetworkRequest(network: networkID))
        let envelope: ActionEnvelope = try await client.send(
            Endpoint(method: .post, path: "/servers/\(serverID)/actions/detach_from_network", body: body)
        )
        return envelope.action
    }

    private func performNetworkAction(networkID: Int, action: String, body: Data?) async throws -> Action {
        let envelope: ActionEnvelope = try await client.send(
            Endpoint(method: .post, path: "/networks/\(networkID)/actions/\(action)", body: body)
        )
        return envelope.action
    }
}

// MARK: - Request bodies

struct CreateNetworkRequest: Encodable, Sendable {
    struct SubnetPayload: Encodable, Sendable {
        let type: String
        let ipRange: String
        let networkZone: String

        enum CodingKeys: String, CodingKey {
            case type
            case ipRange = "ip_range"
            case networkZone = "network_zone"
        }
    }

    let name: String
    let ipRange: String
    let subnets: [SubnetPayload]
    let labels: [String: String]?

    enum CodingKeys: String, CodingKey {
        case name
        case ipRange = "ip_range"
        case subnets, labels
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(ipRange, forKey: .ipRange)
        if !subnets.isEmpty {
            try container.encode(subnets, forKey: .subnets)
        }
        try container.encodeIfPresent(labels, forKey: .labels)
    }
}

struct UpdateNetworkRequest: Encodable, Sendable {
    let name: String?
    let labels: [String: String]?
    let exposeRoutesToVswitch: Bool?

    enum CodingKeys: String, CodingKey {
        case name, labels
        case exposeRoutesToVswitch = "expose_routes_to_vswitch"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(labels, forKey: .labels)
        try container.encodeIfPresent(exposeRoutesToVswitch, forKey: .exposeRoutesToVswitch)
    }
}

struct AddSubnetRequest: Encodable, Sendable {
    let type: String
    let ipRange: String?
    let networkZone: String

    enum CodingKeys: String, CodingKey {
        case type
        case ipRange = "ip_range"
        case networkZone = "network_zone"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(ipRange, forKey: .ipRange)
        try container.encode(networkZone, forKey: .networkZone)
    }
}

struct DeleteSubnetRequest: Encodable, Sendable {
    let ipRange: String
    enum CodingKeys: String, CodingKey { case ipRange = "ip_range" }
}

struct RoutePayloadRequest: Encodable, Sendable {
    let destination: String
    let gateway: String
    enum CodingKeys: String, CodingKey { case destination, gateway }
}

struct AttachToNetworkRequest: Encodable, Sendable {
    let network: Int
    let ip: String?
    let aliasIPs: [String]?

    enum CodingKeys: String, CodingKey {
        case network, ip
        case aliasIPs = "alias_ips"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(network, forKey: .network)
        try container.encodeIfPresent(ip, forKey: .ip)
        try container.encodeIfPresent(aliasIPs, forKey: .aliasIPs)
    }
}

struct DetachFromNetworkRequest: Encodable, Sendable {
    let network: Int
    enum CodingKeys: String, CodingKey { case network }
}
