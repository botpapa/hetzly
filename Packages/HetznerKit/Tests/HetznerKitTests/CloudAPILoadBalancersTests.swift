import Foundation
import Testing
@testable import HetznerKit

@Suite("CloudClient load balancers")
struct CloudAPILoadBalancersTests {
    private func makeClient(responses: [MockTransport.ScriptedResponse]) -> (CloudClient, MockTransport) {
        let transport = MockTransport(responses: responses)
        let client = CloudClient(token: "test-token", transport: transport)
        return (client, transport)
    }

    private func decodedBody(_ requests: [URLRequest], at index: Int = 0) throws -> [String: Any] {
        let data = try #require(requests[index].httpBody)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    @Test func createLoadBalancerSendsNestedServiceAndHealthCheckBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: Self.createResponseJSON()),
        ])

        let service = LBService(
            protocol: .https,
            listenPort: 443,
            destinationPort: 8443,
            proxyprotocol: false,
            http: LBServiceHTTP(
                cookieName: "HCLBSTICKY",
                cookieLifetime: 3600,
                certificates: [1, 2],
                redirectHTTP: true,
                stickySessions: true
            ),
            healthCheck: LBHealthCheck(
                protocol: .http,
                port: 8080,
                interval: 15,
                timeout: 10,
                retries: 3,
                http: LBHealthCheckHTTP(domain: "example.com", path: "/health", response: nil, statusCodes: ["2??", "3??"], tls: false)
            )
        )
        let target = LBTarget(type: .server, server: LBTargetServer(id: 42), labelSelector: nil, ip: nil, usePrivateIP: true, healthStatus: nil)

        let created = try await client.createLoadBalancer(
            name: "web-lb",
            typeName: "lb11",
            algorithmType: .roundRobin,
            locationName: "fsn1",
            networkID: 100,
            services: [service],
            targets: [target],
            labels: ["env": "prod"]
        )

        #expect(created.loadBalancer.id == 1)
        #expect(created.action?.command == "create_load_balancer")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/load_balancers")
        #expect(requests[0].httpMethod == "POST")

        let body = try decodedBody(requests)
        #expect(body["name"] as? String == "web-lb")
        #expect(body["load_balancer_type"] as? String == "lb11")
        #expect((body["algorithm"] as? [String: Any])?["type"] as? String == "round_robin")
        #expect(body["location"] as? String == "fsn1")
        #expect(body["network"] as? Int == 100)

        let services = try #require(body["services"] as? [[String: Any]])
        #expect(services.count == 1)
        #expect(services[0]["protocol"] as? String == "https")
        #expect(services[0]["listen_port"] as? Int == 443)
        let http = try #require(services[0]["http"] as? [String: Any])
        #expect(http["cookie_name"] as? String == "HCLBSTICKY")
        #expect(http["certificates"] as? [Int] == [1, 2])
        let healthCheck = try #require(services[0]["health_check"] as? [String: Any])
        #expect(healthCheck["port"] as? Int == 8080)
        let healthCheckHTTP = try #require(healthCheck["http"] as? [String: Any])
        #expect(healthCheckHTTP["path"] as? String == "/health")
        #expect(healthCheckHTTP["status_codes"] as? [String] == ["2??", "3??"])
        // `response` was nil — the synthesized encoder must omit it, not emit JSON null.
        #expect(healthCheckHTTP["response"] == nil)

        let targets = try #require(body["targets"] as? [[String: Any]])
        #expect(targets[0]["type"] as? String == "server")
        #expect((targets[0]["server"] as? [String: Any])?["id"] as? Int == 42)
        #expect(targets[0]["use_private_ip"] as? Bool == true)
    }

    @Test func decodesFullLoadBalancerRoundTrip() throws {
        let decoder = makeHetznerJSONDecoder()
        let envelope = try decoder.decode(LoadBalancerEnvelope.self, from: Self.loadBalancerEnvelopeJSON())
        let lb = envelope.loadBalancer

        #expect(lb.id == 1)
        #expect(lb.algorithm.type == .roundRobin)
        #expect(lb.publicNet.ipv4?.ip == "1.2.3.4")
        #expect(lb.privateNet.first?.ip == "10.0.0.2")
        #expect(lb.services.first?.listenPort == 443)
        #expect(lb.services.first?.healthCheck?.retries == 3)
        #expect(lb.targets.first?.type == .server)
        #expect(lb.targets.first?.healthStatus?.first?.status == .healthy)
        #expect(lb.loadBalancerType.name == "lb11")
    }

    @Test func unknownAlgorithmTypeDecodesToUnknown() throws {
        let decoder = makeHetznerJSONDecoder()
        let json = Data("""
        {"type": "quantum_routing"}
        """.utf8)
        let algorithm = try decoder.decode(LBAlgorithm.self, from: json)
        #expect(algorithm.type == .unknown)
    }

    @Test func changeLBAlgorithmSendsExpectedBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: Self.actionEnvelopeJSON(command: "change_algorithm")),
        ])

        let action = try await client.changeLBAlgorithm(id: 1, type: .leastConnections)
        #expect(action.command == "change_algorithm")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/load_balancers/1/actions/change_algorithm")
        let body = try decodedBody(requests)
        #expect(body["type"] as? String == "least_connections")
    }

    @Test func addAndRemoveLBTargetRoundTrip() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: Self.actionEnvelopeJSON(command: "add_target")),
            .init(statusCode: 200, data: Self.actionEnvelopeJSON(command: "remove_target")),
        ])

        let target = LBTarget(type: .server, server: LBTargetServer(id: 7), labelSelector: nil, ip: nil, usePrivateIP: nil, healthStatus: nil)
        let addAction = try await client.addLBTarget(id: 1, target: target)
        #expect(addAction.command == "add_target")
        let removeAction = try await client.removeLBTarget(id: 1, target: target)
        #expect(removeAction.command == "remove_target")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/load_balancers/1/actions/add_target")
        #expect(requests[1].url?.absoluteString == "https://api.hetzner.cloud/v1/load_balancers/1/actions/remove_target")

        let addBody = try decodedBody(requests, at: 0)
        #expect((addBody["server"] as? [String: Any])?["id"] as? Int == 7)
        #expect(addBody["label_selector"] == nil)
        #expect(addBody["ip"] == nil)
    }

    @Test func deleteLoadBalancerSendsDELETEAndExpectsNoContent() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 204, data: Data()),
        ])
        try await client.deleteLoadBalancer(id: 3)

        let requests = await transport.recordedRequests
        #expect(requests[0].httpMethod == "DELETE")
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/load_balancers/3")
    }

    /// Load balancer metrics reuse `ServerMetrics`' decode machinery
    /// verbatim — same fixture as the server metrics tests, hit through the
    /// LB-specific endpoint.
    @Test func loadBalancerMetricsDecodesUsingServerMetricsMachinery() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: CloudAPIFixtures.metricsJSON),
        ])

        let metrics = try await client.loadBalancerMetrics(
            id: 1,
            types: [.openConnections, .bandwidth],
            start: Date(timeIntervalSince1970: 1_454_198_400),
            end: Date(timeIntervalSince1970: 1_454_198_700),
            step: 60
        )

        #expect(metrics.series.contains { $0.name == "cpu" })

        let requests = await transport.recordedRequests
        let url = try #require(requests.first?.url)
        #expect(url.path == "/v1/load_balancers/1/metrics")
        let query = try #require(url.query)
        #expect(query.contains("type=bandwidth,open_connections"))
    }

    @Test func listLoadBalancerTypesWalksPagination() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: Self.loadBalancerTypesPageJSON()),
        ])
        let types = try await client.listLoadBalancerTypes()
        #expect(types.count == 1)
        #expect(types[0].name == "lb11")
        #expect(types[0].maxServices == 5)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString.contains("/load_balancer_types") == true)
    }

    // MARK: - Fixtures

    private static func createResponseJSON() -> Data {
        Data(
            """
            {"load_balancer": \(loadBalancerJSON()), "action": {
                "id": 9, "command": "create_load_balancer", "status": "running", "progress": 0,
                "started": "2016-01-30T23:50:00+00:00", "finished": null,
                "resources": [{"id": 1, "type": "load_balancer"}], "error": null
            }}
            """.utf8
        )
    }

    private static func loadBalancerEnvelopeJSON() -> Data {
        Data("{\"load_balancer\": \(loadBalancerJSON())}".utf8)
    }

    private static func loadBalancerJSON() -> String {
        """
        {
            "id": 1, "name": "web-lb",
            "public_net": {"enabled": true, "ipv4": {"ip": "1.2.3.4", "dns_ptr": "lb1.example.com"}, "ipv6": {"ip": "2001:db8::1", "dns_ptr": null}},
            "private_net": [{"network": 100, "ip": "10.0.0.2"}],
            "location": {"id": 1, "name": "fsn1", "description": "Falkenstein DC Park 1", "country": "DE", "city": "Falkenstein", "latitude": 50.47612, "longitude": 12.370071, "network_zone": "eu-central"},
            "load_balancer_type": {"id": 1, "name": "lb11", "description": "LB11", "max_connections": 10000, "max_services": 5, "max_targets": 25, "prices": []},
            "protection": {"delete": false},
            "labels": {"env": "prod"},
            "created": "2016-01-30T23:50:00+00:00",
            "services": [{
                "protocol": "https", "listen_port": 443, "destination_port": 8443, "proxyprotocol": false,
                "http": {"cookie_name": "HCLBSTICKY", "cookie_lifetime": 3600, "certificates": [1], "redirect_http": true, "sticky_sessions": true},
                "health_check": {"protocol": "http", "port": 8080, "interval": 15, "timeout": 10, "retries": 3,
                    "http": {"domain": "example.com", "path": "/health", "response": null, "status_codes": ["2??"], "tls": false}}
            }],
            "targets": [{
                "type": "server", "server": {"id": 42}, "label_selector": null, "ip": null, "use_private_ip": true,
                "health_status": [{"listen_port": 443, "status": "healthy"}]
            }],
            "algorithm": {"type": "round_robin"},
            "outgoing_traffic": 1000, "ingoing_traffic": 2000, "included_traffic": 21990232555520
        }
        """
    }

    private static func actionEnvelopeJSON(command: String) -> Data {
        Data(
            """
            {"action": {
                "id": 1, "command": "\(command)", "status": "running", "progress": 0,
                "started": "2016-01-30T23:50:00+00:00", "finished": null,
                "resources": [{"id": 1, "type": "load_balancer"}], "error": null
            }}
            """.utf8
        )
    }

    private static func loadBalancerTypesPageJSON() -> Data {
        Data(
            """
            {"load_balancer_types": [
                {"id": 1, "name": "lb11", "description": "LB11", "max_connections": 10000, "max_services": 5, "max_targets": 25, "prices": []}
            ], "meta": {"pagination": {"page": 1, "per_page": 50, "previous_page": null, "next_page": null, "last_page": 1, "total_entries": 1}}}
            """.utf8
        )
    }
}
