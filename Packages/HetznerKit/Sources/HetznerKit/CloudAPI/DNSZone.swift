import Foundation

/// A DNS zone, managed via Hetzner's Cloud-integrated DNS API
/// (`api.hetzner.cloud/v1/zones`, same base URL/Bearer auth as the rest of
/// the Cloud API — Hetzner folded DNS into the Cloud API in 2025, replacing
/// the legacy standalone `dns.hetzner.com/api/v1` service; see
/// `docs.hetzner.cloud/reference/cloud#tag/zones`).
public struct DNSZone: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let ttl: Int
    public let mode: DNSZoneMode
    public let status: DNSZoneStatus
    public let recordCount: Int
    public let labels: [String: String]
    public let created: Date
    public let protection: DNSZoneProtection

    enum CodingKeys: String, CodingKey {
        case id, name, ttl, mode, status
        case recordCount = "record_count"
        case labels, created, protection
    }

    public init(
        id: Int,
        name: String,
        ttl: Int,
        mode: DNSZoneMode,
        status: DNSZoneStatus,
        recordCount: Int,
        labels: [String: String],
        created: Date,
        protection: DNSZoneProtection
    ) {
        self.id = id
        self.name = name
        self.ttl = ttl
        self.mode = mode
        self.status = status
        self.recordCount = recordCount
        self.labels = labels
        self.created = created
        self.protection = protection
    }
}

/// Unknown wire values decode to `.unknown` instead of throwing.
public enum DNSZoneMode: String, Codable, Sendable, Equatable {
    case primary, secondary
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DNSZoneMode(rawValue: raw) ?? .unknown
    }
}

/// Unknown wire values decode to `.unknown` instead of throwing.
public enum DNSZoneStatus: String, Codable, Sendable, Equatable {
    case ok, updating, error
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DNSZoneStatus(rawValue: raw) ?? .unknown
    }
}

public struct DNSZoneProtection: Codable, Sendable, Equatable {
    public let delete: Bool

    enum CodingKeys: String, CodingKey { case delete }

    public init(delete: Bool) {
        self.delete = delete
    }
}

/// One DNS resource record set (all records sharing a name + type), managed
/// via `GET/POST/PUT/DELETE /zones/{zoneID}/rrsets/{name}/{type}`. Hetzner
/// also returns a same-shaped `id` field, but every rrset endpoint addresses
/// records by `name`/`type` in the path (see `CloudClient+DNS.swift`), so
/// this model treats `name`+`type` as the effective identity.
public struct DNSRecordSet: Codable, Sendable, Equatable {
    public let name: String
    public let type: DNSRecordType
    public let ttl: Int?
    public let labels: [String: String]
    public let records: [DNSRecordValue]

    enum CodingKeys: String, CodingKey {
        case name, type, ttl, labels, records
    }

    public init(
        name: String,
        type: DNSRecordType,
        ttl: Int?,
        labels: [String: String],
        records: [DNSRecordValue]
    ) {
        self.name = name
        self.type = type
        self.ttl = ttl
        self.labels = labels
        self.records = records
    }
}

/// Unknown wire values decode to `.unknown` instead of throwing. Covers the
/// record types Hetzner's DNS zones support (BIND-file-manageable set:
/// A, AAAA, CAA, CNAME, DS, HINFO, HTTPS, MX, NS, PTR, RP, SOA, SRV, SVCB,
/// TLSA, TXT).
public enum DNSRecordType: String, Codable, Sendable, Equatable {
    case a = "A"
    case aaaa = "AAAA"
    case caa = "CAA"
    case cname = "CNAME"
    case ds = "DS"
    case hinfo = "HINFO"
    case https = "HTTPS"
    case mx = "MX"
    case ns = "NS"
    case ptr = "PTR"
    case rp = "RP"
    case soa = "SOA"
    case srv = "SRV"
    case svcb = "SVCB"
    case tlsa = "TLSA"
    case txt = "TXT"
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DNSRecordType(rawValue: raw) ?? .unknown
    }
}

public struct DNSRecordValue: Codable, Sendable, Equatable {
    public let value: String
    public let comment: String?

    enum CodingKeys: String, CodingKey { case value, comment }

    public init(value: String, comment: String?) {
        self.value = value
        self.comment = comment
    }
}

// MARK: - Envelopes

/// Wire envelope for `GET /zones/{id}` → `{"zone": {...}}`.
struct DNSZoneEnvelope: Decodable, Sendable {
    let zone: DNSZone
}

/// Result of `POST /zones`: the new zone plus its creation action.
public struct CreatedDNSZone: Sendable, Equatable {
    public let zone: DNSZone
    public let action: Action?

    public init(zone: DNSZone, action: Action?) {
        self.zone = zone
        self.action = action
    }
}

struct CreateDNSZoneResponseEnvelope: Decodable, Sendable {
    let zone: DNSZone
    let action: Action?
}

/// Wire envelope for `GET/POST/PUT /zones/{zoneID}/rrsets/{name}/{type}` →
/// `{"rrset": {...}}`.
struct DNSRecordSetEnvelope: Decodable, Sendable {
    let rrset: DNSRecordSet
}
