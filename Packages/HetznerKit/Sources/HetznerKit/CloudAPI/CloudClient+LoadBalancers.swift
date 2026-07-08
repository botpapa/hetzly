import Foundation

/// Metric families available from `GET /load_balancers/{id}/metrics`.
public enum LBMetricsType: String, Sendable, CaseIterable {
    case openConnections = "open_connections"
    case connectionsPerSecond = "connections_per_second"
    case requestsPerSecond = "requests_per_second"
    case bandwidth
}

extension CloudClient {
    /// All load balancers, fully paginated.
    public func listLoadBalancers() async throws -> [LoadBalancer] {
        let stream: AsyncThrowingStream<[LoadBalancer], Error> = paginated(
            client: client,
            endpoint: Endpoint(path: "/load_balancers"),
            itemsKey: "load_balancers",
            perPage: 50
        )

        var loadBalancers: [LoadBalancer] = []
        for try await page in stream {
            loadBalancers.append(contentsOf: page)
        }
        return loadBalancers
    }

    public func loadBalancer(id: Int) async throws -> LoadBalancer {
        let envelope: LoadBalancerEnvelope = try await client.send(Endpoint(path: "/load_balancers/\(id)"))
        return envelope.loadBalancer
    }

    /// All load balancer types (catalog), fully paginated.
    public func listLoadBalancerTypes() async throws -> [LoadBalancerType] {
        let stream: AsyncThrowingStream<[LoadBalancerType], Error> = paginated(
            client: client,
            endpoint: Endpoint(path: "/load_balancer_types"),
            itemsKey: "load_balancer_types",
            perPage: 50
        )

        var types: [LoadBalancerType] = []
        for try await page in stream {
            types.append(contentsOf: page)
        }
        return types
    }

    /// Creates a load balancer. Hetzner returns `201 Created` with the new
    /// load balancer plus a `create_load_balancer` action.
    public func createLoadBalancer(
        name: String,
        typeName: String,
        algorithmType: LBAlgorithmType,
        locationName: String? = nil,
        networkID: Int? = nil,
        services: [LBService] = [],
        targets: [LBTarget] = [],
        labels: [String: String]? = nil
    ) async throws -> CreatedLoadBalancer {
        let request = CreateLoadBalancerRequest(
            name: name,
            loadBalancerType: typeName,
            algorithm: LBAlgorithm(type: algorithmType),
            location: locationName,
            network: networkID,
            services: services.isEmpty ? nil : services,
            targets: targets.isEmpty ? nil : targets,
            labels: labels
        )
        let body = try JSONEncoder().encode(request)
        let envelope: CreateLoadBalancerResponseEnvelope = try await client.send(
            Endpoint(method: .post, path: "/load_balancers", body: body)
        )
        return CreatedLoadBalancer(loadBalancer: envelope.loadBalancer, action: envelope.action)
    }

    /// Hetzner returns `204 No Content` for load balancer deletion.
    public func deleteLoadBalancer(id: Int) async throws {
        try await client.sendExpectingNoContent(Endpoint(method: .delete, path: "/load_balancers/\(id)"))
    }

    public func addLBService(id: Int, service: LBService) async throws -> Action {
        let body = try JSONEncoder().encode(service)
        return try await performLBAction(id: id, action: "add_service", body: body)
    }

    /// Updates an existing service, identified by `service.listenPort`.
    public func updateLBService(id: Int, service: LBService) async throws -> Action {
        let body = try JSONEncoder().encode(service)
        return try await performLBAction(id: id, action: "update_service", body: body)
    }

    public func deleteLBService(id: Int, listenPort: Int) async throws -> Action {
        let body = try JSONEncoder().encode(DeleteLBServiceRequest(listenPort: listenPort))
        return try await performLBAction(id: id, action: "delete_service", body: body)
    }

    public func addLBTarget(id: Int, target: LBTarget) async throws -> Action {
        let body = try JSONEncoder().encode(target)
        return try await performLBAction(id: id, action: "add_target", body: body)
    }

    public func removeLBTarget(id: Int, target: LBTarget) async throws -> Action {
        let body = try JSONEncoder().encode(target)
        return try await performLBAction(id: id, action: "remove_target", body: body)
    }

    public func attachLBToNetwork(id: Int, networkID: Int, ip: String? = nil) async throws -> Action {
        let body = try JSONEncoder().encode(AttachLBToNetworkRequest(network: networkID, ip: ip))
        return try await performLBAction(id: id, action: "attach_to_network", body: body)
    }

    public func detachLBFromNetwork(id: Int, networkID: Int) async throws -> Action {
        let body = try JSONEncoder().encode(DetachLBFromNetworkRequest(network: networkID))
        return try await performLBAction(id: id, action: "detach_from_network", body: body)
    }

    public func changeLBAlgorithm(id: Int, type: LBAlgorithmType) async throws -> Action {
        let body = try JSONEncoder().encode(ChangeLBAlgorithmRequest(type: type.rawValue))
        return try await performLBAction(id: id, action: "change_algorithm", body: body)
    }

    public func changeLBType(id: Int, typeName: String) async throws -> Action {
        let body = try JSONEncoder().encode(ChangeLBTypeRequest(loadBalancerType: typeName))
        return try await performLBAction(id: id, action: "change_type", body: body)
    }

    public func changeLBProtection(id: Int, delete: Bool) async throws -> Action {
        let body = try JSONEncoder().encode(ChangeLBProtectionRequest(delete: delete))
        return try await performLBAction(id: id, action: "change_protection", body: body)
    }

    /// Load balancer metrics — same wire shape as `serverMetrics`
    /// (`{"metrics": {start, end, step, time_series: {...}}}`), so this
    /// reuses `ServerMetrics`'s decoding directly.
    public func loadBalancerMetrics(
        id: Int,
        types: Set<LBMetricsType>,
        start: Date,
        end: Date,
        step: TimeInterval
    ) async throws -> ServerMetrics {
        let typeParam = types.map(\.rawValue).sorted().joined(separator: ",")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let query = [
            URLQueryItem(name: "type", value: typeParam),
            URLQueryItem(name: "start", value: formatter.string(from: start)),
            URLQueryItem(name: "end", value: formatter.string(from: end)),
            URLQueryItem(name: "step", value: String(Int(step))),
        ]
        return try await client.send(Endpoint(path: "/load_balancers/\(id)/metrics", query: query))
    }

    private func performLBAction(id: Int, action: String, body: Data?) async throws -> Action {
        let envelope: ActionEnvelope = try await client.send(
            Endpoint(method: .post, path: "/load_balancers/\(id)/actions/\(action)", body: body)
        )
        return envelope.action
    }
}

// MARK: - Request bodies

struct CreateLoadBalancerRequest: Encodable, Sendable {
    let name: String
    let loadBalancerType: String
    let algorithm: LBAlgorithm
    let location: String?
    let network: Int?
    let services: [LBService]?
    let targets: [LBTarget]?
    let labels: [String: String]?

    enum CodingKeys: String, CodingKey {
        case name
        case loadBalancerType = "load_balancer_type"
        case algorithm, location, network, services, targets, labels
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(loadBalancerType, forKey: .loadBalancerType)
        try container.encode(algorithm, forKey: .algorithm)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(network, forKey: .network)
        try container.encodeIfPresent(services, forKey: .services)
        try container.encodeIfPresent(targets, forKey: .targets)
        try container.encodeIfPresent(labels, forKey: .labels)
    }
}

struct DeleteLBServiceRequest: Encodable, Sendable {
    let listenPort: Int
    enum CodingKeys: String, CodingKey { case listenPort = "listen_port" }
}

struct AttachLBToNetworkRequest: Encodable, Sendable {
    let network: Int
    let ip: String?

    enum CodingKeys: String, CodingKey { case network, ip }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(network, forKey: .network)
        try container.encodeIfPresent(ip, forKey: .ip)
    }
}

struct DetachLBFromNetworkRequest: Encodable, Sendable {
    let network: Int
    enum CodingKeys: String, CodingKey { case network }
}

struct ChangeLBAlgorithmRequest: Encodable, Sendable {
    let type: String
    enum CodingKeys: String, CodingKey { case type }
}

struct ChangeLBTypeRequest: Encodable, Sendable {
    let loadBalancerType: String
    enum CodingKeys: String, CodingKey { case loadBalancerType = "load_balancer_type" }
}

struct ChangeLBProtectionRequest: Encodable, Sendable {
    let delete: Bool
    enum CodingKeys: String, CodingKey { case delete }
}
