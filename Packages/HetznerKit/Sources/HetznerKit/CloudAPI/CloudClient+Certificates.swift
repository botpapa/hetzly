import Foundation

extension CloudClient {
    /// All certificates, fully paginated.
    public func listCertificates() async throws -> [Certificate] {
        let stream: AsyncThrowingStream<[Certificate], Error> = paginated(
            client: client,
            endpoint: Endpoint(path: "/certificates"),
            itemsKey: "certificates",
            perPage: 50
        )

        var certificates: [Certificate] = []
        for try await page in stream {
            certificates.append(contentsOf: page)
        }
        return certificates
    }

    public func certificate(id: Int) async throws -> Certificate {
        let envelope: CertificateEnvelope = try await client.send(Endpoint(path: "/certificates/\(id)"))
        return envelope.certificate
    }

    /// Requests a Hetzner-managed certificate (auto-issued and renewed via
    /// Let's Encrypt). Hetzner returns `201 Created` with the certificate
    /// (initially unissued) plus a `create_certificate` action tracking
    /// issuance.
    public func createManagedCertificate(
        name: String,
        domainNames: [String],
        labels: [String: String]? = nil
    ) async throws -> CreatedCertificate {
        let request = CreateManagedCertificateRequest(name: name, domainNames: domainNames, labels: labels)
        let body = try JSONEncoder().encode(request)
        let envelope: CreateCertificateResponseEnvelope = try await client.send(
            Endpoint(method: .post, path: "/certificates", body: body)
        )
        return CreatedCertificate(certificate: envelope.certificate, action: envelope.action)
    }

    /// Uploads a caller-supplied certificate + private key. Synchronous — no
    /// action is queued. The private key is used only to build the request
    /// body; it is never logged, never round-tripped back from the API, and
    /// never retained by this client after the call returns.
    public func uploadCertificate(
        name: String,
        certificate: String,
        privateKey: String,
        labels: [String: String]? = nil
    ) async throws -> Certificate {
        let request = UploadCertificateRequest(name: name, certificate: certificate, privateKey: privateKey, labels: labels)
        let body = try JSONEncoder().encode(request)
        let envelope: CertificateEnvelope = try await client.send(
            Endpoint(method: .post, path: "/certificates", body: body)
        )
        return envelope.certificate
    }

    /// Renames and/or relabels a certificate via `PUT /certificates/{id}`.
    public func updateCertificate(
        id: Int,
        name: String? = nil,
        labels: [String: String]? = nil
    ) async throws -> Certificate {
        let request = UpdateCertificateRequest(name: name, labels: labels)
        let body = try JSONEncoder().encode(request)
        let envelope: CertificateEnvelope = try await client.send(
            Endpoint(method: .put, path: "/certificates/\(id)", body: body)
        )
        return envelope.certificate
    }

    /// Hetzner returns `204 No Content` for certificate deletion.
    public func deleteCertificate(id: Int) async throws {
        try await client.sendExpectingNoContent(Endpoint(method: .delete, path: "/certificates/\(id)"))
    }
}

// MARK: - Request bodies

struct CreateManagedCertificateRequest: Encodable, Sendable {
    let name: String
    let type = "managed"
    let domainNames: [String]
    let labels: [String: String]?

    enum CodingKeys: String, CodingKey {
        case name, type
        case domainNames = "domain_names"
        case labels
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(domainNames, forKey: .domainNames)
        try container.encodeIfPresent(labels, forKey: .labels)
    }
}

/// Request body for `POST /certificates` with `type: "uploaded"`.
///
/// Deliberately NOT `CustomStringConvertible`/`CustomDebugStringConvertible`
/// via synthesis — a hand-written, redacting conformance is provided below
/// so that any accidental `"\(request)"`/`print(request)`/debugger
/// interpolation never surfaces `privateKey`. This is on top of the global
/// rule that request bodies containing secrets are never logged.
struct UploadCertificateRequest: Encodable, Sendable {
    let name: String
    let type = "uploaded"
    let certificate: String
    let privateKey: String
    let labels: [String: String]?

    enum CodingKeys: String, CodingKey {
        case name, type, certificate
        case privateKey = "private_key"
        case labels
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(certificate, forKey: .certificate)
        try container.encode(privateKey, forKey: .privateKey)
        try container.encodeIfPresent(labels, forKey: .labels)
    }
}

extension UploadCertificateRequest: CustomStringConvertible, CustomDebugStringConvertible {
    var description: String {
        "UploadCertificateRequest(name: \(name), type: \(type), certificate: <\(certificate.count) chars>, privateKey: <redacted>, labels: \(labels ?? [:]))"
    }

    var debugDescription: String { description }
}

struct UpdateCertificateRequest: Encodable, Sendable {
    let name: String?
    let labels: [String: String]?

    enum CodingKeys: String, CodingKey { case name, labels }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(labels, forKey: .labels)
    }
}
