import Foundation
import Testing
@testable import HetznerKit

@Suite("CloudClient+Images / +Catalog (M2 Wave A)")
struct CloudAPIImagesTests {
    private func makeClient(responses: [MockTransport.ScriptedResponse]) -> (CloudClient, MockTransport) {
        let transport = MockTransport(responses: responses)
        let client = CloudClient(token: "test-token", transport: transport)
        return (client, transport)
    }

    private func bodyJSON(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    private func imageJSON(id: Int, type: String = "snapshot", name: String? = "my-image") -> String {
        let nameValue = name.map { "\"\($0)\"" } ?? "null"
        return """
        {
            "id": \(id), "type": "\(type)", "status": "available", "name": \(nameValue),
            "description": "desc-\(id)", "image_size": 2.3, "disk_size": 40.0,
            "created": "2016-01-30T23:50:00+00:00", "created_from": null,
            "bound_to": null, "os_flavor": "ubuntu", "os_version": "24.04",
            "architecture": "x86", "protection": {"delete": false}, "deprecated": null,
            "labels": {}
        }
        """
    }

    private func imagesPageJSON(ids: [Int], nextPage: Int?) -> Data {
        let items = ids.map { imageJSON(id: $0) }.joined(separator: ",")
        let nextString = nextPage.map(String.init) ?? "null"
        let json = """
        {
            "images": [\(items)],
            "meta": {
                "pagination": {
                    "page": 1, "per_page": 50, "previous_page": null,
                    "next_page": \(nextString), "last_page": 2, "total_entries": \(ids.count)
                }
            }
        }
        """
        return Data(json.utf8)
    }

    // MARK: - listImages

    @Test func listImagesWalksAllPages() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: imagesPageJSON(ids: [1, 2], nextPage: 2)),
            .init(statusCode: 200, data: imagesPageJSON(ids: [3], nextPage: nil)),
        ])

        let images = try await client.listImages()
        #expect(images.map(\.id).sorted() == [1, 2, 3])

        let requests = await transport.recordedRequests
        #expect(requests.count == 2)
        #expect(requests[0].url?.absoluteString.contains("/images") == true)
        #expect(requests[0].url?.query?.contains("sort=created:desc") == true)
    }

    @Test func listImagesAppliesTypeFilterQuery() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: imagesPageJSON(ids: [1], nextPage: nil)),
        ])

        _ = try await client.listImages(type: .snapshot)

        let requests = await transport.recordedRequests
        let query = try #require(requests[0].url?.query)
        #expect(query.contains("type=snapshot"))
    }

    @Test func imageFetchesSingleImageByID() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: Data("{\"image\": \(imageJSON(id: 42))}".utf8)),
        ])

        let image = try await client.image(id: 42)
        #expect(image.id == 42)
        #expect(image.type == .snapshot)
        #expect(image.status == .available)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/images/42")
    }

    @Test func imageDecodesUnknownTypeAndStatusToUnknownCase() async throws {
        let (client, _) = makeClient(responses: [
            .init(statusCode: 200, data: Data("{\"image\": \(imageJSON(id: 42, type: "totally-new-type"))}".utf8)),
        ])
        let image = try await client.image(id: 42)
        #expect(image.type == .unknown)
    }

    @Test func deleteImageSendsDELETEAndExpectsNoContent() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 204, data: Data()),
        ])

        try await client.deleteImage(id: 42)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/images/42")
        #expect(requests[0].httpMethod == "DELETE")
    }

    @Test func updateImageSendsPUTBodyAndDecodesImage() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: Data("{\"image\": \(imageJSON(id: 42, name: "renamed"))}".utf8)),
        ])

        let image = try await client.updateImage(id: 42, description: "renamed", labels: ["k": "v"])
        #expect(image.id == 42)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/images/42")
        #expect(requests[0].httpMethod == "PUT")
        let body = try bodyJSON(requests[0])
        #expect(body["description"] as? String == "renamed")
        #expect(body["labels"] as? [String: String] == ["k": "v"])
    }

    @Test func changeImageProtectionPostsDeleteBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: CloudAPIFixtures.actionEnvelopeJSON(command: "change_protection")),
        ])

        let action = try await client.changeImageProtection(id: 42, delete: true)
        #expect(action.command == "change_protection")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/images/42/actions/change_protection")
        let body = try bodyJSON(requests[0])
        #expect(body["delete"] as? Bool == true)
    }

    // MARK: - Catalog: ISOs, server types, locations, datacenters

    @Test func listISOsDecodesPublicPrivateAndDeprecation() async throws {
        let json = """
        {
            "isos": [
                {
                    "id": 1, "name": "FreeBSD", "description": "FreeBSD ISO",
                    "type": "public", "architecture": "x86",
                    "deprecation": {"unavailable_after": "2018-02-28T00:00:00+00:00", "announced": "2017-08-01T00:00:00+00:00"}
                },
                {
                    "id": 2, "name": null, "description": null,
                    "type": "private", "architecture": null, "deprecation": null
                }
            ],
            "meta": {"pagination": {"page": 1, "per_page": 50, "previous_page": null, "next_page": null, "last_page": 1, "total_entries": 2}}
        }
        """
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: Data(json.utf8)),
        ])

        let isos = try await client.listISOs()
        #expect(isos.count == 2)
        #expect(isos[0].type == .public)
        #expect(isos[0].deprecation?.announced != nil)
        #expect(isos[1].type == .private)
        #expect(isos[1].architecture == nil)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString.contains("/isos") == true)
    }

    @Test func listServerTypesWalksPagination() async throws {
        func page(id: Int, nextPage: Int?) -> Data {
            let nextString = nextPage.map(String.init) ?? "null"
            let json = """
            {
                "server_types": [\(CloudAPIFixtures.serverTypeJSON(id: id, name: "type-\(id)"))],
                "meta": {"pagination": {"page": 1, "per_page": 50, "previous_page": null, "next_page": \(nextString), "last_page": 2, "total_entries": 1}}
            }
            """
            return Data(json.utf8)
        }
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: page(id: 1, nextPage: 2)),
            .init(statusCode: 200, data: page(id: 2, nextPage: nil)),
        ])

        let types = try await client.listServerTypes()
        #expect(types.map(\.id).sorted() == [1, 2])

        let requests = await transport.recordedRequests
        #expect(requests.count == 2)
        #expect(requests[0].url?.absoluteString.contains("/server_types") == true)
    }

    @Test func listLocationsAndDatacentersHitExpectedPaths() async throws {
        let locationsJSON = Data("""
        {
            "locations": [{"id": 1, "name": "fsn1", "description": "Falkenstein", "country": "DE", "city": "Falkenstein", "latitude": 50.47, "longitude": 12.37, "network_zone": "eu-central"}],
            "meta": {"pagination": {"page": 1, "per_page": 50, "previous_page": null, "next_page": null, "last_page": 1, "total_entries": 1}}
        }
        """.utf8)
        let datacentersJSON = Data("""
        {
            "datacenters": [\(CloudAPIFixtures.datacenterJSON)],
            "meta": {"pagination": {"page": 1, "per_page": 50, "previous_page": null, "next_page": null, "last_page": 1, "total_entries": 1}}
        }
        """.utf8)

        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: locationsJSON),
            .init(statusCode: 200, data: datacentersJSON),
        ])

        let locations = try await client.listLocations()
        #expect(locations.map(\.name) == ["fsn1"])

        let datacenters = try await client.listDatacenters()
        #expect(datacenters.map(\.id) == [1])

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString.contains("/locations") == true)
        #expect(requests[1].url?.absoluteString.contains("/datacenters") == true)
    }
}
