import Foundation
import Testing
@testable import HetznerKit

/// Fixtures matching the *live* (2026) Hetzner Cloud API shape, as observed
/// against a real (read-only) token during a live-API compatibility audit.
/// All ids/IPs/names here are fake/synthetic — never real account data.
///
/// Confirmed drift from the shapes `CloudAPIFixtures` (used by the older
/// `CloudAPI*Tests` suites) models:
///   - `Server`/`PrimaryIP` no longer have a `datacenter` object; instead
///     there's a top-level `location` object.
///   - Empty `labels` can come back as `[]` (a JSON array) instead of `{}`.
///   - `server_type` gained `category`, `storage_type`, `deprecation`
///     (object), and `locations` (per-location availability) fields.
///   - `Server` gained several new top-level keys this package doesn't map
///     (`image`, `iso`, `volumes`, `load_balancers`, `private_net`,
///     `placement_group`) — Codable ignores unmapped keys by default, so
///     these just need to not break decoding.
private enum LiveShapeFixtures {
    /// Top-level `location` object, as it now appears directly on `Server`
    /// and `PrimaryIP` responses (previously nested under `datacenter`).
    static let locationJSON = """
    {
        "id": 3,
        "name": "hel1",
        "description": "Helsinki DC Park 1",
        "country": "FI",
        "city": "Helsinki",
        "latitude": 60.169855,
        "longitude": 24.938379,
        "network_zone": "eu-central"
    }
    """

    /// `server_type` embedded shape with every field the 2026 API adds.
    static let serverTypeJSON = """
    {
        "id": 105,
        "name": "cx32",
        "description": "CX32",
        "cores": 4,
        "memory": 8,
        "disk": 80,
        "cpu_type": "shared",
        "architecture": "x86",
        "category": "cost_optimized",
        "deprecated": true,
        "deprecation": {
            "announced": "2025-10-16T06:00:00Z",
            "unavailable_after": "2025-12-31T23:59:59Z"
        },
        "storage_type": "local",
        "locations": [
            {
                "id": 1,
                "name": "fsn1",
                "available": false,
                "recommended": false,
                "deprecation": {
                    "announced": "2025-10-16T06:00:00Z",
                    "unavailable_after": "2025-12-31T23:59:59Z"
                }
            },
            {
                "id": 4,
                "name": "ash",
                "available": true,
                "recommended": true,
                "deprecation": null
            }
        ],
        "prices": [
            {
                "location": "fsn1",
                "price_hourly": {"net": "0.0136000000", "gross": "0.0136000000000000"},
                "price_monthly": {"net": "8.4900000000", "gross": "8.4900000000000000"},
                "included_traffic": 21990232555520,
                "price_per_tb_traffic": {"net": "1.0000000000", "gross": "1.0000000000000000"}
            }
        ]
    }
    """

    /// A full server body in the *new* (2026) shape: no `datacenter` key,
    /// a top-level `location` object instead, empty `labels` as `[]`, and
    /// several new/unmapped top-level keys mixed in.
    static func serverJSONNewShape(id: Int = 42, name: String = "web-01") -> String {
        """
        {
            "id": \(id),
            "name": "\(name)",
            "status": "running",
            "created": "2016-01-30T23:50:00+00:00",
            "public_net": {
                "ipv4": {"ip": "203.0.113.10"},
                "ipv6": {"ip": "2001:db8::/64"}
            },
            "server_type": \(serverTypeJSON),
            "location": \(locationJSON),
            "labels": [],
            "locked": false,
            "protection": {"delete": false, "rebuild": false},
            "backup_window": null,
            "rescue_enabled": false,
            "primary_disk_size": 80,
            "included_traffic": 21990232555520,
            "outgoing_traffic": null,
            "ingoing_traffic": null,
            "image": null,
            "iso": null,
            "volumes": [],
            "load_balancers": [],
            "private_net": [],
            "placement_group": null
        }
        """
    }

    static func serverEnvelopeJSONNewShape(id: Int = 42, name: String = "web-01") -> Data {
        Data("{\"server\": \(serverJSONNewShape(id: id, name: name))}".utf8)
    }

    /// A primary IP body in the new shape: no `datacenter` key, top-level
    /// `location` instead, empty `labels` as `[]`.
    static func primaryIPJSONNewShape(id: Int = 7) -> String {
        """
        {
            "id": \(id),
            "name": "primary-ip-\(id)",
            "ip": "203.0.113.20",
            "type": "ipv4",
            "assignee_id": 42,
            "assignee_type": "server",
            "auto_delete": true,
            "blocked": false,
            "created": "2024-12-12T17:12:25Z",
            "location": \(locationJSON),
            "dns_ptr": [{"ip": "203.0.113.20", "dns_ptr": "static.example.invalid"}],
            "labels": [],
            "protection": {"delete": false}
        }
        """
    }

    static func primaryIPEnvelopeJSONNewShape(id: Int = 7) -> Data {
        Data("{\"primary_ip\": \(primaryIPJSONNewShape(id: id))}".utf8)
    }

    static func imageJSON(labels: String) -> String {
        """
        {
            "id": 99,
            "type": "snapshot",
            "status": "available",
            "name": null,
            "description": "web-01 snapshot",
            "image_size": 5.1,
            "disk_size": 40.0,
            "created": "2016-01-30T23:50:00+00:00",
            "created_from": {"id": 42, "name": "web-01"},
            "bound_to": null,
            "os_flavor": "ubuntu",
            "os_version": "24.04",
            "architecture": "x86",
            "protection": {"delete": false},
            "deprecated": null,
            "labels": \(labels)
        }
        """
    }

    static func firewallJSON(labels: String) -> String {
        """
        {
            "id": 5,
            "name": "web-fw",
            "labels": \(labels),
            "created": "2016-01-30T23:50:00+00:00",
            "rules": [],
            "applied_to": []
        }
        """
    }
}

@Suite("CloudAPI live-shape (2026 API drift) decoding")
struct CloudAPILiveShapeTests {
    private let decoder = makeHetznerJSONDecoder()

    // MARK: - Server: datacenter → top-level location

    @Test func decodesServerWithTopLevelLocationInsteadOfDatacenter() throws {
        let data = LiveShapeFixtures.serverEnvelopeJSONNewShape()
        let envelope = try decoder.decode(ServerEnvelope.self, from: data)
        let server = envelope.server

        // Synthesized placeholder Datacenter — never real API data.
        #expect(server.datacenter.id == -1)
        #expect(server.datacenter.name == "hel1-dc")
        #expect(server.datacenter.description == "")

        // The real location data flows through both the synthesized
        // `datacenter.location` and the new `location` convenience.
        #expect(server.datacenter.location.name == "hel1")
        #expect(server.datacenter.location.city == "Helsinki")
        #expect(server.location.city == "Helsinki")
        #expect(server.location.country == "FI")
        #expect(server.location == server.datacenter.location)
    }

    @Test func decodesServerToleratingUnmappedTopLevelKeys() throws {
        // image/iso/volumes/load_balancers/private_net/placement_group are
        // all present in the fixture but not modeled — must not throw.
        let data = LiveShapeFixtures.serverEnvelopeJSONNewShape()
        let envelope = try decoder.decode(ServerEnvelope.self, from: data)
        #expect(envelope.server.id == 42)
    }

    @Test func oldShapeServerFixtureStillDecodesWithRealDatacenter() throws {
        // Reuses the shared old-shape fixture (has an explicit "datacenter"
        // key) to prove the back-compat path didn't regress it.
        let data = CloudAPIFixtures.serverEnvelopeJSON()
        let envelope = try decoder.decode(ServerEnvelope.self, from: data)
        let server = envelope.server

        #expect(server.datacenter.id == 1)
        #expect(server.datacenter.name == "fsn1-dc14")
        #expect(server.location == server.datacenter.location)
        #expect(server.location.city == "Falkenstein")
        #expect(server.labels == ["env": "prod"])
    }

    // MARK: - Labels: tolerant of `[]` for empty

    @Test func decodesServerWithEmptyArrayLabels() throws {
        let data = LiveShapeFixtures.serverEnvelopeJSONNewShape()
        let envelope = try decoder.decode(ServerEnvelope.self, from: data)
        #expect(envelope.server.labels == [:])
    }

    @Test func decodesImageWithEmptyArrayLabels() throws {
        let json = Data(LiveShapeFixtures.imageJSON(labels: "[]").utf8)
        let image = try decoder.decode(Image.self, from: json)
        #expect(image.labels == [:])
    }

    @Test func decodesImageWithObjectLabelsUnchanged() throws {
        let json = Data(LiveShapeFixtures.imageJSON(labels: #"{"env": "prod"}"#).utf8)
        let image = try decoder.decode(Image.self, from: json)
        #expect(image.labels == ["env": "prod"])
    }

    @Test func decodesFirewallWithEmptyArrayLabels() throws {
        let json = Data(LiveShapeFixtures.firewallJSON(labels: "[]").utf8)
        let firewall = try decoder.decode(Firewall.self, from: json)
        #expect(firewall.labels == [:])
    }

    @Test func nonEmptyArrayLabelsStillThrowsInsteadOfSilentlyDroppingData() throws {
        // A non-empty array isn't a shape we can recover from — must still
        // surface a decoding error rather than silently discarding labels.
        let json = Data(LiveShapeFixtures.imageJSON(labels: #"["not", "a", "dictionary"]"#).utf8)
        #expect(throws: (any Error).self) {
            try decoder.decode(Image.self, from: json)
        }
    }

    // MARK: - PrimaryIP: datacenter → top-level location, labels as []

    @Test func decodesPrimaryIPWithTopLevelLocationInsteadOfDatacenter() throws {
        let data = LiveShapeFixtures.primaryIPEnvelopeJSONNewShape()
        let envelope = try decoder.decode(PrimaryIPEnvelope.self, from: data)
        let primaryIP = envelope.primaryIP

        #expect(primaryIP.datacenter.id == -1)
        #expect(primaryIP.datacenter.name == "hel1-dc")
        #expect(primaryIP.location.city == "Helsinki")
        #expect(primaryIP.location == primaryIP.datacenter.location)
        #expect(primaryIP.labels == [:])
    }

    // MARK: - ServerType: category/storage_type/deprecation/locations

    @Test func decodesServerTypeWithCategoryDeprecationAndLocations() throws {
        let json = Data(LiveShapeFixtures.serverTypeJSON.utf8)
        let serverType = try decoder.decode(ServerType.self, from: json)

        #expect(serverType.category == "cost_optimized")
        #expect(serverType.storageType == "local")
        #expect(serverType.deprecated == true)
        #expect(serverType.deprecation?.announced != nil)
        #expect(serverType.locations?.count == 2)
        #expect(serverType.locations?.first?.name == "fsn1")
        #expect(serverType.locations?.first?.available == false)
        #expect(serverType.locations?.last?.recommended == true)
        #expect(serverType.locations?.last?.deprecation == nil)
    }

    @Test func oldShapeServerTypeFixtureStillDecodesWithNilNewFields() throws {
        let json = Data(CloudAPIFixtures.serverTypeJSON().utf8)
        let serverType = try decoder.decode(ServerType.self, from: json)

        #expect(serverType.deprecated == false)
        #expect(serverType.category == nil)
        #expect(serverType.storageType == nil)
        #expect(serverType.deprecation == nil)
        #expect(serverType.locations == nil)
    }
}
