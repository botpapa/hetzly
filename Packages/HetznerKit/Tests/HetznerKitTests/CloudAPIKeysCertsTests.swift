import Foundation
import Testing
@testable import HetznerKit

@Suite("CloudClient SSH keys + certificates")
struct CloudAPIKeysCertsTests {
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

    // MARK: - SSH keys

    @Test func createSSHKeySendsExpectedBodyAndDecodesResponse() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: Self.sshKeyEnvelopeJSON(id: 1, name: "laptop")),
        ])

        let key = try await client.createSSHKey(
            name: "laptop",
            publicKey: "ssh-ed25519 AAAAC3...",
            labels: ["owner": "andrew"]
        )

        #expect(key.id == 1)
        #expect(key.fingerprint == "aa:bb:cc")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/ssh_keys")
        #expect(requests[0].httpMethod == "POST")

        let body = try decodedBody(requests)
        #expect(body["name"] as? String == "laptop")
        #expect(body["public_key"] as? String == "ssh-ed25519 AAAAC3...")
        #expect((body["labels"] as? [String: String])?["owner"] == "andrew")
    }

    @Test func updateSSHKeySendsPUTWithOnlyProvidedFields() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: Self.sshKeyEnvelopeJSON(id: 1, name: "renamed")),
        ])

        _ = try await client.updateSSHKey(id: 1, name: "renamed")

        let requests = await transport.recordedRequests
        #expect(requests[0].httpMethod == "PUT")
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/ssh_keys/1")

        let body = try decodedBody(requests)
        #expect(body["name"] as? String == "renamed")
        #expect(body["labels"] == nil)
    }

    @Test func deleteSSHKeySendsDELETEAndExpectsNoContent() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 204, data: Data()),
        ])

        try await client.deleteSSHKey(id: 1)

        let requests = await transport.recordedRequests
        #expect(requests[0].httpMethod == "DELETE")
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/ssh_keys/1")
    }

    @Test func listSSHKeysWalksPagination() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: Self.sshKeysPageJSON(keys: [(1, "a"), (2, "b")], nextPage: 2)),
            .init(statusCode: 200, data: Self.sshKeysPageJSON(keys: [(3, "c")], nextPage: nil)),
        ])

        let keys = try await client.listSSHKeys()
        #expect(keys.count == 3)

        let requests = await transport.recordedRequests
        #expect(requests.count == 2)
    }

    // MARK: - Certificates

    @Test func uploadCertificateSendsPrivateKeyInBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: Self.certificateEnvelopeJSON(id: 1, type: "uploaded")),
        ])

        _ = try await client.uploadCertificate(
            name: "web-cert",
            certificate: "-----BEGIN CERTIFICATE-----\nMIIB...\n-----END CERTIFICATE-----",
            privateKey: "-----BEGIN PRIVATE KEY-----\nTOP-SECRET-KEY-MATERIAL\n-----END PRIVATE KEY-----"
        )

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/certificates")
        #expect(requests[0].httpMethod == "POST")

        let body = try decodedBody(requests)
        #expect(body["type"] as? String == "uploaded")
        #expect((body["private_key"] as? String)?.contains("TOP-SECRET-KEY-MATERIAL") == true)
        #expect((body["certificate"] as? String)?.contains("BEGIN CERTIFICATE") == true)
    }

    /// The private key is a secret that must never leak through incidental
    /// string interpolation (`print(request)`, debugger `po`, log
    /// statements accidentally left in). `UploadCertificateRequest` provides
    /// a hand-written, redacting `CustomStringConvertible`/
    /// `CustomDebugStringConvertible` conformance for exactly this reason.
    @Test func uploadCertificateRequestDescriptionRedactsPrivateKey() throws {
        let secret = "TOP-SECRET-KEY-MATERIAL-\(UUID().uuidString)"
        let request = UploadCertificateRequest(
            name: "web-cert",
            certificate: "-----BEGIN CERTIFICATE-----\nMIIB...\n-----END CERTIFICATE-----",
            privateKey: secret,
            labels: nil
        )

        #expect(!"\(request)".contains(secret))
        #expect(!request.debugDescription.contains(secret))
        #expect("\(request)".contains("redacted"))
    }

    @Test func createManagedCertificateSendsDomainNamesAndDecodesQueuedAction() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: Self.createManagedCertificateResponseJSON()),
        ])

        let created = try await client.createManagedCertificate(
            name: "managed-cert",
            domainNames: ["example.com", "www.example.com"]
        )

        #expect(created.certificate.type == .managed)
        #expect(created.certificate.domainNames == ["example.com", "www.example.com"])
        #expect(created.action?.command == "create_certificate")
        #expect(created.certificate.status?.issuance == .pending)

        let requests = await transport.recordedRequests
        let body = try decodedBody(requests)
        #expect(body["type"] as? String == "managed")
        #expect(body["domain_names"] as? [String] == ["example.com", "www.example.com"])
    }

    @Test func deleteCertificateSendsDELETEAndExpectsNoContent() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 204, data: Data()),
        ])
        try await client.deleteCertificate(id: 9)

        let requests = await transport.recordedRequests
        #expect(requests[0].httpMethod == "DELETE")
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/certificates/9")
    }

    @Test func unknownCertificateTypeDecodesToUnknown() throws {
        let decoder = makeHetznerJSONDecoder()
        let data = Self.certificateEnvelopeJSON(id: 1, type: "quantum")
        let envelope = try decoder.decode(CertificateEnvelope.self, from: data)
        #expect(envelope.certificate.type == .unknown)
    }

    // MARK: - Fixtures

    private static func sshKeyEnvelopeJSON(id: Int, name: String) -> Data {
        Data(
            """
            {"ssh_key": {"id": \(id), "name": "\(name)", "fingerprint": "aa:bb:cc",
             "public_key": "ssh-ed25519 AAAAC3...", "labels": {}, "created": "2016-01-30T23:50:00+00:00"}}
            """.utf8
        )
    }

    private static func sshKeysPageJSON(keys: [(id: Int, name: String)], nextPage: Int?) -> Data {
        let items = keys.map {
            """
            {"id": \($0.id), "name": "\($0.name)", "fingerprint": "aa:bb:cc",
             "public_key": "ssh-ed25519 AAAAC3...", "labels": {}, "created": "2016-01-30T23:50:00+00:00"}
            """
        }.joined(separator: ",")
        let nextString = nextPage.map(String.init) ?? "null"
        return Data(
            """
            {"ssh_keys": [\(items)], "meta": {"pagination": {
                "page": 1, "per_page": 50, "previous_page": null,
                "next_page": \(nextString), "last_page": 2, "total_entries": \(keys.count)
            }}}
            """.utf8
        )
    }

    private static func certificateEnvelopeJSON(id: Int, type: String) -> Data {
        Data(
            """
            {"certificate": {
                "id": \(id), "name": "web-cert", "labels": {}, "type": "\(type)",
                "certificate": "-----BEGIN CERTIFICATE-----\\nMIIB...\\n-----END CERTIFICATE-----",
                "created": "2016-01-30T23:50:00+00:00",
                "not_valid_before": "2016-01-30T23:50:00+00:00",
                "not_valid_after": "2016-04-30T23:50:00+00:00",
                "domain_names": ["example.com"],
                "fingerprint": "03:c7:55:9b",
                "status": null
            }}
            """.utf8
        )
    }

    private static func createManagedCertificateResponseJSON() -> Data {
        Data(
            """
            {
                "certificate": {
                    "id": 2, "name": "managed-cert", "labels": {}, "type": "managed",
                    "certificate": null, "created": "2016-01-30T23:50:00+00:00",
                    "not_valid_before": null, "not_valid_after": null,
                    "domain_names": ["example.com", "www.example.com"],
                    "fingerprint": null,
                    "status": {"issuance": "pending", "renewal": "pending"}
                },
                "action": {
                    "id": 5, "command": "create_certificate", "status": "running", "progress": 0,
                    "started": "2016-01-30T23:50:00+00:00", "finished": null,
                    "resources": [{"id": 2, "type": "certificate"}], "error": null
                }
            }
            """.utf8
        )
    }
}
