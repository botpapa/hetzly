import Foundation
import HetznerKit

/// Preview-only mock data for the DNS feature. No network access — every
/// `#Preview` in this directory renders from these fixtures.
enum DNSPreviewFixtures {
    static let now = Date()

    static let zone = DNSZone(
        id: 501,
        name: "example.com",
        ttl: 3_600,
        mode: .primary,
        status: .ok,
        recordCount: 8,
        labels: [:],
        created: now.addingTimeInterval(-90 * 24 * 3_600),
        protection: DNSZoneProtection(delete: false)
    )

    static let updatingZone = DNSZone(
        id: 502,
        name: "staging-example.dev",
        ttl: 300,
        mode: .primary,
        status: .updating,
        recordCount: 3,
        labels: [:],
        created: now.addingTimeInterval(-2 * 24 * 3_600),
        protection: DNSZoneProtection(delete: false)
    )

    static let recordSets: [DNSRecordSet] = [
        DNSRecordSet(
            name: "@",
            type: .a,
            ttl: 3_600,
            labels: [:],
            records: [DNSRecordValue(value: "203.0.113.10", comment: nil)]
        ),
        DNSRecordSet(
            name: "@",
            type: .aaaa,
            ttl: 3_600,
            labels: [:],
            records: [DNSRecordValue(value: "2001:db8:4f9:c012:4a2b:9df8:12aa:1", comment: nil)]
        ),
        DNSRecordSet(
            name: "www",
            type: .cname,
            ttl: 300,
            labels: [:],
            records: [DNSRecordValue(value: "example.com.", comment: nil)]
        ),
        DNSRecordSet(
            name: "@",
            type: .mx,
            ttl: 3_600,
            labels: [:],
            records: [
                DNSRecordValue(value: "10 mail.example.com.", comment: nil),
                DNSRecordValue(value: "20 backup-mail.example.com.", comment: nil),
            ]
        ),
        DNSRecordSet(
            name: "@",
            type: .txt,
            ttl: 86_400,
            labels: [:],
            records: [
                DNSRecordValue(value: "v=spf1 include:_spf.example.com include:amazonses.com ~all", comment: nil),
            ]
        ),
        DNSRecordSet(
            name: "@",
            type: .ns,
            ttl: 86_400,
            labels: [:],
            records: [
                DNSRecordValue(value: "hydrogen.ns.hetzner.com.", comment: nil),
                DNSRecordValue(value: "oxygen.ns.hetzner.com.", comment: nil),
                DNSRecordValue(value: "helium.ns.hetzner.de.", comment: nil),
            ]
        ),
    ]
}
