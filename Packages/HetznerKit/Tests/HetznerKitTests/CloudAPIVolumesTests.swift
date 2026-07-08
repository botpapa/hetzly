import Foundation
import Testing
@testable import HetznerKit

/// Fixtures local to this file — shared `CloudAPIFixtures` is owned by
/// another worker and must not be modified.
private enum VolumeFixtures {
    static let locationJSON = """
    {
        "id": 1,
        "name": "fsn1",
        "description": "Falkenstein DC Park 1",
        "country": "DE",
        "city": "Falkenstein",
        "latitude": 50.47612,
        "longitude": 12.370071,
        "network_zone": "eu-central"
    }
    """

    static func volumeJSON(id: Int = 100, name: String = "vol1", server: Int? = 42, status: String = "available") -> String {
        let serverValue = server.map(String.init) ?? "null"
        return """
        {
            "id": \(id),
            "created": "2016-01-30T23:50:00+00:00",
            "name": "\(name)",
            "server": \(serverValue),
            "location": \(locationJSON),
            "size": 10,
            "linux_device": "/dev/disk/by-id/scsi-0HC_Volume_\(id)",
            "protection": {"delete": false},
            "status": "\(status)",
            "format": "ext4",
            "labels": {"env": "prod"}
        }
        """
    }

    static func volumeEnvelopeJSON(id: Int = 100, name: String = "vol1", server: Int? = 42) -> Data {
        Data("{\"volume\": \(volumeJSON(id: id, name: name, server: server))}".utf8)
    }

    static func volumesPageJSON(volumes: [(id: Int, name: String)], nextPage: Int?) -> Data {
        let items = volumes.map { volumeJSON(id: $0.id, name: $0.name) }.joined(separator: ",")
        let nextString = nextPage.map(String.init) ?? "null"
        let json = """
        {
            "volumes": [\(items)],
            "meta": {
                "pagination": {
                    "page": 1, "per_page": 50, "previous_page": null,
                    "next_page": \(nextString), "last_page": 2, "total_entries": \(volumes.count)
                }
            }
        }
        """
        return Data(json.utf8)
    }

    static func createVolumeResponseJSON(id: Int = 100, server: Int?, action: String?, nextActions: [String]) -> Data {
        let actionValue = action.map { "{\"id\": 1, \"command\": \"\($0)\", \"status\": \"running\", \"progress\": 0, \"started\": \"2016-01-30T23:50:00+00:00\", \"finished\": null, \"resources\": [], \"error\": null}" } ?? "null"
        let nextActionsValue = nextActions.isEmpty
            ? "[]"
            : "[" + nextActions.map { "{\"id\": 2, \"command\": \"\($0)\", \"status\": \"running\", \"progress\": 0, \"started\": \"2016-01-30T23:50:00+00:00\", \"finished\": null, \"resources\": [], \"error\": null}" }.joined(separator: ",") + "]"
        let json = """
        {
            "volume": \(volumeJSON(id: id, server: server)),
            "action": \(actionValue),
            "next_actions": \(nextActionsValue)
        }
        """
        return Data(json.utf8)
    }
}

@Suite("CloudClient+Volumes")
struct CloudAPIVolumesTests {
    private func makeClient(responses: [MockTransport.ScriptedResponse]) -> (CloudClient, MockTransport) {
        let transport = MockTransport(responses: responses)
        let client = CloudClient(token: "test-token", transport: transport)
        return (client, transport)
    }

    private func decodedBody(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    @Test func listVolumesWalksAllPages() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: VolumeFixtures.volumesPageJSON(volumes: [(1, "a"), (2, "b")], nextPage: 2)),
            .init(statusCode: 200, data: VolumeFixtures.volumesPageJSON(volumes: [(3, "c")], nextPage: nil)),
        ])

        let volumes = try await client.listVolumes()

        #expect(volumes.map(\.id) == [1, 2, 3])

        let requests = await transport.recordedRequests
        #expect(requests.count == 2)
        #expect(requests[0].url?.absoluteString.contains("/volumes") == true)
        #expect(requests[0].httpMethod == "GET")
    }

    @Test func volumeFetchesSingleByID() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: VolumeFixtures.volumeEnvelopeJSON(id: 55, name: "solo")),
        ])
        let volume = try await client.volume(id: 55)
        #expect(volume.id == 55)
        #expect(volume.name == "solo")
        #expect(volume.location.name == "fsn1")
        #expect(volume.linuxDevice.contains("scsi"))
        #expect(volume.status == .available)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/volumes/55")
    }

    @Test func createVolumeWithLocationSendsExpectedBodyAndDecodesImmediateAction() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: VolumeFixtures.createVolumeResponseJSON(server: nil, action: "create_volume", nextActions: [])),
        ])

        let created = try await client.createVolume(name: "backups", size: 20, locationName: "fsn1", format: "ext4")

        #expect(created.volume.name == "vol1")
        #expect(created.action?.command == "create_volume")
        #expect(created.nextActions.isEmpty)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/volumes")
        #expect(requests[0].httpMethod == "POST")

        let body = try decodedBody(requests[0])
        #expect(body["name"] as? String == "backups")
        #expect(body["size"] as? Int == 20)
        #expect(body["location"] as? String == "fsn1")
        #expect(body["format"] as? String == "ext4")
        #expect(body["server"] == nil)
    }

    @Test func createVolumeWithServerIDQueuesNextActions() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: VolumeFixtures.createVolumeResponseJSON(server: 42, action: nil, nextActions: ["attach_volume"])),
        ])

        let created = try await client.createVolume(name: "data", size: 50, serverID: 42, automount: true)

        #expect(created.action == nil)
        #expect(created.nextActions.map(\.command) == ["attach_volume"])

        let requests = await transport.recordedRequests
        let body = try decodedBody(requests[0])
        #expect(body["server"] as? Int == 42)
        #expect(body["automount"] as? Bool == true)
        #expect(body["location"] == nil)
    }

    @Test func deleteVolumeSendsDELETEAndExpectsNoContent() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 204, data: Data()),
        ])

        try await client.deleteVolume(id: 100)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/volumes/100")
        #expect(requests[0].httpMethod == "DELETE")
    }

    @Test func resizeVolumeSendsActionPathAndSizeBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: actionEnvelope(command: "resize_volume")),
        ])

        let action = try await client.resizeVolume(id: 100, size: 30)
        #expect(action.command == "resize_volume")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/volumes/100/actions/resize")
        #expect(requests[0].httpMethod == "POST")
        let body = try decodedBody(requests[0])
        #expect(body["size"] as? Int == 30)
    }

    @Test func attachVolumeSendsServerAndAutomountBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: actionEnvelope(command: "attach_volume")),
        ])

        let action = try await client.attachVolume(id: 100, serverID: 7, automount: false)
        #expect(action.command == "attach_volume")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/volumes/100/actions/attach")
        let body = try decodedBody(requests[0])
        #expect(body["server"] as? Int == 7)
        #expect(body["automount"] as? Bool == false)
    }

    @Test func detachVolumeSendsNoBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: actionEnvelope(command: "detach_volume")),
        ])

        let action = try await client.detachVolume(id: 100)
        #expect(action.command == "detach_volume")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/volumes/100/actions/detach")
        #expect(requests[0].httpBody == nil)
    }

    @Test func changeVolumeProtectionSendsDeleteBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: actionEnvelope(command: "change_protection")),
        ])

        _ = try await client.changeVolumeProtection(id: 100, delete: true)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/volumes/100/actions/change_protection")
        let body = try decodedBody(requests[0])
        #expect(body["delete"] as? Bool == true)
    }

    @Test func updateVolumeRenamesAndRelabelsViaPUT() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: VolumeFixtures.volumeEnvelopeJSON(id: 100, name: "renamed")),
        ])

        let volume = try await client.updateVolume(id: 100, name: "renamed", labels: ["a": "b"])
        #expect(volume.name == "renamed")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/volumes/100")
        #expect(requests[0].httpMethod == "PUT")
        let body = try decodedBody(requests[0])
        #expect(body["name"] as? String == "renamed")
        #expect((body["labels"] as? [String: String])?["a"] == "b")
    }

    @Test func updateVolumeLabelsOmitsNameFromBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: VolumeFixtures.volumeEnvelopeJSON()),
        ])

        _ = try await client.updateVolumeLabels(id: 100, labels: ["env": "staging"])

        let requests = await transport.recordedRequests
        let body = try decodedBody(requests[0])
        #expect(body["name"] == nil)
        #expect((body["labels"] as? [String: String])?["env"] == "staging")
    }

    private func actionEnvelope(command: String) -> Data {
        Data(
            """
            {"action": {"id": 1, "command": "\(command)", "status": "running", "progress": 0, "started": "2016-01-30T23:50:00+00:00", "finished": null, "resources": [{"id": 100, "type": "volume"}], "error": null}}
            """.utf8
        )
    }
}
