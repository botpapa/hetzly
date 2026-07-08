import HetznerKit
import SwiftUI

/// Light, per-type validation for DNS record values. Deliberately
/// permissive — the API remains the source of truth — but catches the
/// obvious mistakes (an IPv6 in an A record, a bare IP in a CNAME, ...).
enum DNSRecordValidator {
    static func isValid(_ value: String, for type: DNSRecordType) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        switch type {
        case .a:
            return isIPv4(trimmed)
        case .aaaa:
            return isIPv6(trimmed)
        case .cname, .ns, .ptr:
            return isHostname(trimmed)
        case .mx:
            // "10 mail.example.com." — priority validated separately in the
            // editor; here accept the combined wire form.
            let parts = trimmed.split(separator: " ")
            guard parts.count == 2, let priority = Int(parts[0]), (0...65_535).contains(priority) else {
                return false
            }
            return isHostname(String(parts[1]))
        default:
            // TXT and the long tail (SRV, CAA, TLSA, ...) are free-form here.
            return true
        }
    }

    static func isIPv4(_ value: String) -> Bool {
        let octets = value.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return false }
        return octets.allSatisfy { octet in
            guard !octet.isEmpty, octet.count <= 3, octet.allSatisfy(\.isNumber), let number = Int(octet) else {
                return false
            }
            if octet.count > 1, octet.first == "0" { return false }
            return (0...255).contains(number)
        }
    }

    static func isIPv6(_ value: String) -> Bool {
        if value == "::" { return true }
        let doubleColonCount = value.components(separatedBy: "::").count - 1
        guard doubleColonCount <= 1 else { return false }
        if value.hasPrefix(":"), !value.hasPrefix("::") { return false }
        if value.hasSuffix(":"), !value.hasSuffix("::") { return false }
        let groups = value
            .components(separatedBy: "::")
            .flatMap { $0.split(separator: ":", omittingEmptySubsequences: true) }
        guard !groups.isEmpty || doubleColonCount == 1 else { return false }
        guard groups.count <= 8 else { return false }
        if doubleColonCount == 0, groups.count != 8 { return false }
        return groups.allSatisfy { (1...4).contains($0.count) && $0.allSatisfy(\.isHexDigit) }
    }

    /// Accepts absolute ("mail.example.com.") and relative hostnames, and
    /// "@" for the zone apex.
    static func isHostname(_ value: String) -> Bool {
        if value == "@" { return true }
        var host = value
        if host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty, host.count <= 253 else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { label in
            guard (1...63).contains(label.count) else { return false }
            guard label.first != "-", label.last != "-" else { return false }
            return label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "*" }
        }
    }
}

extension DNSRecordType {
    /// Record types offered in the add-record picker, most common first.
    static let editableCases: [DNSRecordType] = [.a, .aaaa, .cname, .mx, .txt, .ns, .srv, .caa]

    /// Per-type placeholder for the value field.
    var valuePlaceholder: String {
        switch self {
        case .a: "203.0.113.10"
        case .aaaa: "2001:db8::1"
        case .cname: "target.example.com."
        case .mx: "mail.example.com."
        case .txt: "v=spf1 include:_spf.example.com ~all"
        case .ns: "ns1.example.com."
        case .srv: "10 5 5060 sip.example.com."
        case .caa: "0 issue \"letsencrypt.org\""
        default: "value"
        }
    }

    /// Types edited as one value per line in a multi-line editor (TXT and
    /// the free-form tail); A/AAAA/CNAME/MX get dedicated single fields.
    var usesMultilineValues: Bool {
        switch self {
        case .a, .aaaa, .cname, .mx: false
        default: true
        }
    }
}

extension DNSZoneStatus {
    var resourceStatus: ResourceStatus {
        switch self {
        case .ok: .running
        case .updating: .transitioning
        case .error: .error
        case .unknown: .unknown
        }
    }

    var displayName: String {
        switch self {
        case .ok: "OK"
        case .updating: "Updating"
        case .error: "Error"
        case .unknown: "Unknown"
        }
    }
}

/// TTL choices offered by the record editor.
enum TTLPreset: CaseIterable, Identifiable {
    case fiveMinutes
    case oneHour
    case oneDay
    case custom

    var id: Int {
        switch self {
        case .fiveMinutes: 300
        case .oneHour: 3_600
        case .oneDay: 86_400
        case .custom: -1
        }
    }

    var label: String {
        switch self {
        case .fiveMinutes: "5 min"
        case .oneHour: "1 hour"
        case .oneDay: "1 day"
        case .custom: "Custom"
        }
    }

    var seconds: Int? {
        switch self {
        case .fiveMinutes: 300
        case .oneHour: 3_600
        case .oneDay: 86_400
        case .custom: nil
        }
    }

    static func matching(ttl: Int?) -> TTLPreset {
        switch ttl {
        case 300: .fiveMinutes
        case 3_600: .oneHour
        case 86_400: .oneDay
        case nil: .oneHour
        default: .custom
        }
    }
}

/// "1h" / "300s" style compact TTL label for record chips.
enum TTLFormatter {
    static func compact(_ ttl: Int) -> String {
        if ttl % 86_400 == 0 { return "\(ttl / 86_400)d" }
        if ttl % 3_600 == 0 { return "\(ttl / 3_600)h" }
        if ttl % 60 == 0 { return "\(ttl / 60)m" }
        return "\(ttl)s"
    }
}

/// Middle-truncates long record values (TXT blobs, IPv6) so both the
/// distinctive start and end stay visible.
enum RecordValueFormatter {
    static func middleTruncated(_ value: String, limit: Int = 42) -> String {
        guard value.count > limit else { return value }
        let keep = (limit - 1) / 2
        return "\(value.prefix(keep))…\(value.suffix(keep))"
    }
}
