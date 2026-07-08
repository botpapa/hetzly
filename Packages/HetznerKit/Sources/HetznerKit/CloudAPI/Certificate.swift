import Foundation

/// A Hetzner Cloud TLS certificate — either uploaded by the caller or
/// Hetzner-managed (auto-issued/renewed via Let's Encrypt).
///
/// `certificate` (the PEM-encoded public certificate) and `fingerprint` are
/// populated once available; for a freshly-requested managed certificate
/// they may be `nil` until `status.issuance` completes. The private key
/// supplied when uploading a certificate is never part of this model — it is
/// a request-body-only secret (see `CloudClient.uploadCertificate`).
public struct Certificate: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let labels: [String: String]
    public let type: CertificateType
    public let certificate: String?
    public let created: Date
    public let notValidBefore: Date?
    public let notValidAfter: Date?
    public let domainNames: [String]
    public let fingerprint: String?
    /// Managed-certificate issuance/renewal state. `nil` for uploaded certs.
    public let status: CertificateStatus?

    enum CodingKeys: String, CodingKey {
        case id, name, labels, type, certificate, created
        case notValidBefore = "not_valid_before"
        case notValidAfter = "not_valid_after"
        case domainNames = "domain_names"
        case fingerprint, status
    }

    public init(
        id: Int,
        name: String,
        labels: [String: String],
        type: CertificateType,
        certificate: String?,
        created: Date,
        notValidBefore: Date?,
        notValidAfter: Date?,
        domainNames: [String],
        fingerprint: String?,
        status: CertificateStatus?
    ) {
        self.id = id
        self.name = name
        self.labels = labels
        self.type = type
        self.certificate = certificate
        self.created = created
        self.notValidBefore = notValidBefore
        self.notValidAfter = notValidAfter
        self.domainNames = domainNames
        self.fingerprint = fingerprint
        self.status = status
    }

    /// Labels decode leniently — see `decodeLenientLabels`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        labels = try container.decodeLenientLabels(forKey: .labels)
        type = try container.decode(CertificateType.self, forKey: .type)
        certificate = try container.decodeIfPresent(String.self, forKey: .certificate)
        created = try container.decode(Date.self, forKey: .created)
        notValidBefore = try container.decodeIfPresent(Date.self, forKey: .notValidBefore)
        notValidAfter = try container.decodeIfPresent(Date.self, forKey: .notValidAfter)
        domainNames = try container.decode([String].self, forKey: .domainNames)
        fingerprint = try container.decodeIfPresent(String.self, forKey: .fingerprint)
        status = try container.decodeIfPresent(CertificateStatus.self, forKey: .status)
    }
}

/// Unknown wire values decode to `.unknown` instead of throwing.
public enum CertificateType: String, Codable, Sendable, Equatable {
    case uploaded, managed
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CertificateType(rawValue: raw) ?? .unknown
    }
}

/// Issuance/renewal progress for a Hetzner-managed certificate.
public struct CertificateStatus: Codable, Sendable, Equatable {
    public let issuance: CertificateProcessStatus
    public let renewal: CertificateProcessStatus

    enum CodingKeys: String, CodingKey { case issuance, renewal }

    public init(issuance: CertificateProcessStatus, renewal: CertificateProcessStatus) {
        self.issuance = issuance
        self.renewal = renewal
    }
}

/// Unknown wire values decode to `.unknown` instead of throwing.
public enum CertificateProcessStatus: String, Codable, Sendable, Equatable {
    case pending, completed, failed
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CertificateProcessStatus(rawValue: raw) ?? .unknown
    }
}

/// Wire envelope for `GET/POST/PUT /certificates/{id}` → `{"certificate": {...}}`.
struct CertificateEnvelope: Decodable, Sendable {
    let certificate: Certificate
}

/// Result of `POST /certificates`: an uploaded certificate is created
/// synchronously (no action); a managed certificate queues an issuance
/// action.
public struct CreatedCertificate: Sendable, Equatable {
    public let certificate: Certificate
    public let action: Action?

    public init(certificate: Certificate, action: Action?) {
        self.certificate = certificate
        self.action = action
    }
}

struct CreateCertificateResponseEnvelope: Decodable, Sendable {
    let certificate: Certificate
    let action: Action?
}
