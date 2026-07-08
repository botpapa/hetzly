import Foundation
import Testing
@testable import HetznerKit

/// Covers the Cloud-integrated DNS API (`/zones`, `/zones/{id}/rrsets`),
/// which shares `api.hetzner.cloud/v1`'s base URL and Bearer auth — Hetzner
/// folded the previously-standalone `dns.hetzner.com/api/v1` service into
/// the Cloud API in 2025 (`docs.hetzner.cloud/reference/cloud#tag/zones`;
/// `hetznercloud/hcloud-go`'s `hcloud/zone.go` and `hcloud/zone_rrset.go`
/// were used to confirm exact field/path shapes since the interactive docs
/// don't statically render their JSON schema for fetch tools).
@Suite("CloudClient DNS zones")
struct CloudAPIDNSTests {
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

    @Test func decodesZone() throws {
        let decoder = makeHetznerJSONDecoder()
        let envelope = try decoder.decode(DNSZoneEnvelope.self, from: Self.zoneEnvelopeJSON())
        let zone = envelope.zone

        #expect(zone.id == 42)
        #expect(zone.name == "example.com")
        #expect(zone.ttl == 3600)
        #expect(zone.mode == .primary)
        #expect(zone.status == .ok)
        #expect(zone.recordCount == 5)
        #expect(zone.protection.delete == false)
    }

    @Test func unknownZoneStatusDecodesToUnknown() throws {
        let decoder = makeHetznerJSONDecoder()
        let json = Self.zoneEnvelopeJSON(status: "reticulating")
        let envelope = try decoder.decode(DNSZoneEnvelope.self, from: json)
        #expect(envelope.zone.status == .unknown)
    }

    @Test func decodesRecordSetWithMultipleRecordsAndUnknownType() throws {
        let decoder = makeHetznerJSONDecoder()
        let json = Data(
            """
            {"rrset": {
                "name": "www", "type": "A", "ttl": 300, "labels": {},
                "records": [{"value": "1.2.3.4", "comment": "primary"}, {"value": "1.2.3.5", "comment": null}]
            }}
            """.utf8
        )
        let envelope = try decoder.decode(DNSRecordSetEnvelope.self, from: json)
        #expect(envelope.rrset.name == "www")
        #expect(envelope.rrset.type == .a)
        #expect(envelope.rrset.records.count == 2)
        #expect(envelope.rrset.records[0].value == "1.2.3.4")
        #expect(envelope.rrset.records[1].comment == nil)

        let unknownTypeJSON = Data(
            """
            {"rrset": {"name": "www", "type": "FUTURE_TYPE", "ttl": null, "labels": {}, "records": []}}
            """.utf8
        )
        let unknownEnvelope = try decoder.decode(DNSRecordSetEnvelope.self, from: unknownTypeJSON)
        #expect(unknownEnvelope.rrset.type == .unknown)
    }

    @Test func createZoneSendsExpectedBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: Self.createZoneResponseJSON()),
        ])

        let created = try await client.createZone(name: "example.com", ttl: 3600, labels: ["env": "prod"])
        #expect(created.zone.name == "example.com")
        #expect(created.action?.command == "create_zone")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/zones")
        #expect(requests[0].httpMethod == "POST")

        let body = try decodedBody(requests)
        #expect(body["name"] as? String == "example.com")
        #expect(body["mode"] as? String == "primary")
        #expect(body["ttl"] as? Int == 3600)
    }

    @Test func createRecordSetSendsNestedRecordsBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: Self.recordSetEnvelopeJSON()),
        ])

        let rrset = try await client.createRecordSet(
            zoneID: 42,
            name: "www",
            type: .a,
            records: [DNSRecordValue(value: "1.2.3.4", comment: nil)],
            ttl: 300
        )
        #expect(rrset.name == "www")
        #expect(rrset.type == .a)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/zones/42/rrsets")
        #expect(requests[0].httpMethod == "POST")

        let body = try decodedBody(requests)
        #expect(body["name"] as? String == "www")
        #expect(body["type"] as? String == "A")
        let records = try #require(body["records"] as? [[String: Any]])
        #expect(records[0]["value"] as? String == "1.2.3.4")
    }

    @Test func updateRecordSetSendsPUTToNameAndTypePath() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: Self.recordSetEnvelopeJSON()),
        ])

        _ = try await client.updateRecordSet(
            zoneID: 42,
            name: "www",
            type: .a,
            records: [DNSRecordValue(value: "5.6.7.8", comment: "updated")]
        )

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/zones/42/rrsets/www/A")
        #expect(requests[0].httpMethod == "PUT")

        let body = try decodedBody(requests)
        // Identity (name/type) travels in the path, not the PUT body.
        #expect(body["name"] == nil)
        #expect(body["type"] == nil)
        let records = try #require(body["records"] as? [[String: Any]])
        #expect(records[0]["value"] as? String == "5.6.7.8")
    }

    @Test func deleteRecordSetSendsDELETEToNameAndTypePathAndExpectsNoContent() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 204, data: Data()),
        ])

        try await client.deleteRecordSet(zoneID: 42, name: "www", type: .cname)

        let requests = await transport.recordedRequests
        #expect(requests[0].httpMethod == "DELETE")
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/zones/42/rrsets/www/CNAME")
    }

    @Test func listZonesWalksPagination() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: Self.zonesPageJSON()),
        ])
        let zones = try await client.listZones()
        #expect(zones.count == 1)
        #expect(zones[0].name == "example.com")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString.contains("/zones") == true)
    }

    @Test func deleteZoneSendsDELETEAndExpectsNoContent() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 204, data: Data()),
        ])
        try await client.deleteZone(id: 42)

        let requests = await transport.recordedRequests
        #expect(requests[0].httpMethod == "DELETE")
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/zones/42")
    }

    // MARK: - Fixtures

    private static func zoneJSON(status: String = "ok") -> String {
        """
        {
            "id": 42, "name": "example.com", "ttl": 3600, "mode": "primary", "status": "\(status)",
            "record_count": 5, "labels": {}, "created": "2016-01-30T23:50:00+00:00",
            "protection": {"delete": false}
        }
        """
    }

    private static func zoneEnvelopeJSON(status: String = "ok") -> Data {
        Data("{\"zone\": \(zoneJSON(status: status))}".utf8)
    }

    private static func zonesPageJSON() -> Data {
        Data(
            """
            {"zones": [\(zoneJSON())], "meta": {"pagination": {
                "page": 1, "per_page": 50, "previous_page": null, "next_page": null, "last_page": 1, "total_entries": 1
            }}}
            """.utf8
        )
    }

    private static func createZoneResponseJSON() -> Data {
        Data(
            """
            {"zone": \(zoneJSON()), "action": {
                "id": 1, "command": "create_zone", "status": "running", "progress": 0,
                "started": "2016-01-30T23:50:00+00:00", "finished": null,
                "resources": [{"id": 42, "type": "zone"}], "error": null
            }}
            """.utf8
        )
    }

    private static func recordSetEnvelopeJSON() -> Data {
        Data(
            """
            {"rrset": {"name": "www", "type": "A", "ttl": 300, "labels": {}, "records": [{"value": "1.2.3.4", "comment": null}]}}
            """.utf8
        )
    }
}
