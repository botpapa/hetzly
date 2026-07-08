import Foundation

extension CloudClient {
    /// All firewalls, fully paginated.
    public func listFirewalls() async throws -> [Firewall] {
        let stream: AsyncThrowingStream<[Firewall], Error> = paginated(
            client: client,
            endpoint: Endpoint(path: "/firewalls"),
            itemsKey: "firewalls",
            perPage: 50
        )

        var firewalls: [Firewall] = []
        for try await page in stream {
            firewalls.append(contentsOf: page)
        }
        return firewalls
    }

    public func firewall(id: Int) async throws -> Firewall {
        let envelope: FirewallEnvelope = try await client.send(Endpoint(path: "/firewalls/\(id)"))
        return envelope.firewall
    }

    /// Creates a firewall. `applyTo` is optional at creation time — firewalls
    /// can also be created bare and attached later via `applyFirewall`.
    public func createFirewall(
        name: String,
        rules: [FirewallRule] = [],
        applyTo: [FirewallApplyTarget] = [],
        labels: [String: String]? = nil
    ) async throws -> CreatedFirewall {
        let request = CreateFirewallRequest(
            name: name,
            labels: labels,
            rules: rules,
            applyTo: applyTo.map(\.payload)
        )
        let body = try JSONEncoder().encode(request)
        let envelope: CreateFirewallResponseEnvelope = try await client.send(
            Endpoint(method: .post, path: "/firewalls", body: body)
        )
        return CreatedFirewall(firewall: envelope.firewall, actions: envelope.actions)
    }

    /// Hetzner returns `204 No Content` for firewall deletion.
    public func deleteFirewall(id: Int) async throws {
        try await client.sendExpectingNoContent(Endpoint(method: .delete, path: "/firewalls/\(id)"))
    }

    public func updateFirewall(
        id: Int,
        name: String? = nil,
        labels: [String: String]? = nil
    ) async throws -> Firewall {
        let body = try JSONEncoder().encode(UpdateFirewallRequest(name: name, labels: labels))
        let envelope: FirewallEnvelope = try await client.send(
            Endpoint(method: .put, path: "/firewalls/\(id)", body: body)
        )
        return envelope.firewall
    }

    /// Replaces the firewall's rule set. Unlike most action endpoints this
    /// returns `{"actions": [...]}` (plural) — one action per resource the
    /// firewall is currently applied to.
    public func setFirewallRules(id: Int, rules: [FirewallRule]) async throws -> [Action] {
        let body = try JSONEncoder().encode(SetFirewallRulesRequest(rules: rules))
        return try await performFirewallActions(
            Endpoint(method: .post, path: "/firewalls/\(id)/actions/set_rules", body: body)
        )
    }

    /// Applies the firewall to servers and/or label selectors.
    public func applyFirewall(
        id: Int,
        toServerIDs: [Int] = [],
        labelSelectors: [String] = []
    ) async throws -> [Action] {
        let targets = Self.firewallTargets(serverIDs: toServerIDs, labelSelectors: labelSelectors)
        let body = try JSONEncoder().encode(ApplyToResourcesRequest(applyTo: targets.map(\.payload)))
        return try await performFirewallActions(
            Endpoint(method: .post, path: "/firewalls/\(id)/actions/apply_to_resources", body: body)
        )
    }

    /// Removes the firewall from servers and/or label selectors.
    public func removeFirewall(
        id: Int,
        fromServerIDs: [Int] = [],
        labelSelectors: [String] = []
    ) async throws -> [Action] {
        let targets = Self.firewallTargets(serverIDs: fromServerIDs, labelSelectors: labelSelectors)
        let body = try JSONEncoder().encode(RemoveFromResourcesRequest(removeFrom: targets.map(\.payload)))
        return try await performFirewallActions(
            Endpoint(method: .post, path: "/firewalls/\(id)/actions/remove_from_resources", body: body)
        )
    }

    private static func firewallTargets(serverIDs: [Int], labelSelectors: [String]) -> [FirewallApplyTarget] {
        serverIDs.map { FirewallApplyTarget.server(id: $0) } + labelSelectors.map { FirewallApplyTarget.labelSelector($0) }
    }

    private func performFirewallActions(_ endpoint: Endpoint) async throws -> [Action] {
        let envelope: FirewallActionsEnvelope = try await client.send(endpoint)
        return envelope.actions
    }
}

// MARK: - Request bodies

struct CreateFirewallRequest: Encodable, Sendable {
    let name: String
    let labels: [String: String]?
    let rules: [FirewallRule]
    let applyTo: [FirewallApplyToPayload]

    enum CodingKeys: String, CodingKey {
        case name, labels, rules
        case applyTo = "apply_to"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(labels, forKey: .labels)
        try container.encode(rules, forKey: .rules)
        if !applyTo.isEmpty {
            try container.encode(applyTo, forKey: .applyTo)
        }
    }
}

struct UpdateFirewallRequest: Encodable, Sendable {
    let name: String?
    let labels: [String: String]?

    enum CodingKeys: String, CodingKey { case name, labels }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(labels, forKey: .labels)
    }
}

struct SetFirewallRulesRequest: Encodable, Sendable {
    let rules: [FirewallRule]
}

struct ApplyToResourcesRequest: Encodable, Sendable {
    let applyTo: [FirewallApplyToPayload]
    enum CodingKeys: String, CodingKey { case applyTo = "apply_to" }
}

struct RemoveFromResourcesRequest: Encodable, Sendable {
    let removeFrom: [FirewallApplyToPayload]
    enum CodingKeys: String, CodingKey { case removeFrom = "remove_from" }
}

/// One entry of a firewall's `apply_to` / `apply_to_resources` /
/// `remove_from_resources` request arrays.
struct FirewallApplyToPayload: Encodable, Sendable {
    let type: String
    let server: FirewallServerRefPayload?
    let labelSelector: FirewallLabelSelectorPayload?

    enum CodingKeys: String, CodingKey {
        case type, server
        case labelSelector = "label_selector"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(server, forKey: .server)
        try container.encodeIfPresent(labelSelector, forKey: .labelSelector)
    }
}

struct FirewallServerRefPayload: Encodable, Sendable {
    let id: Int
}

struct FirewallLabelSelectorPayload: Encodable, Sendable {
    let selector: String
}
