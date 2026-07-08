import Foundation

// MARK: - Lenient labels decoding
//
// Hetzner's Cloud API represents an empty `labels` map as `{}` on most
// endpoints. Live-API testing against the 2026 API (see Worker A1 audit,
// live-shape drift notes) observed at least one response shape returning an
// empty label set as `[]` (a JSON array) instead of `{}` (a JSON object).
// Every model with a `labels` field decodes through this helper so a `[]`
// payload degrades to `[:]` instead of throwing
// `DecodingError.typeMismatch`. Any other malformed shape (e.g. a
// non-empty array) still throws, surfacing a real problem instead of
// silently losing data.
extension KeyedDecodingContainer {
    func decodeLenientLabels(forKey key: Key) throws -> [String: String] {
        do {
            return try decode([String: String].self, forKey: key)
        } catch DecodingError.typeMismatch {
            let array = try decode([String].self, forKey: key)
            guard array.isEmpty else {
                throw DecodingError.typeMismatch(
                    [String: String].self,
                    DecodingError.Context(
                        codingPath: codingPath + [key],
                        debugDescription:
                            "Expected labels as an object (e.g. {\"k\":\"v\"}) or an empty array ([]); got a non-empty array."
                    )
                )
            }
            return [:]
        }
    }
}

// MARK: - `datacenter` → top-level `location` synthesis
//
// The 2026 Hetzner Cloud API dropped the `datacenter` object from `Server`
// and `PrimaryIP` responses in favor of a top-level `location` object.
// These models keep their existing `datacenter: Datacenter` stored property
// (so `server.datacenter.location.city`, `CostItemBuilder`'s
// `datacenter.location.name` price matching, etc. keep compiling and
// working unmodified) but synthesize a placeholder `Datacenter` when only
// `location` is present on the wire:
//
//     Datacenter(id: -1, name: "<location.name>-dc", description: "", location: location)
//
// `id == -1` and the `-dc`-suffixed `name` are never real Hetzner data —
// they only exist so old call sites that dot into `.datacenter.id` /
// `.datacenter.name` don't crash. Prefer the `location` computed property
// each affected model exposes (`server.location`, `primaryIP.location`) for
// anything that doesn't specifically need the (now largely synthetic,
// post-drift) `Datacenter` wrapper — and never display the synthesized
// `name`/`id` in UI as if they were real API data.
enum DatacenterLocationCodingKey: String, CodingKey {
    case datacenter
    case location
}

func decodeDatacenterOrSynthesize(from decoder: Decoder) throws -> Datacenter {
    let container = try decoder.container(keyedBy: DatacenterLocationCodingKey.self)
    if let datacenter = try container.decodeIfPresent(Datacenter.self, forKey: .datacenter) {
        return datacenter
    }
    let location = try container.decode(Location.self, forKey: .location)
    return Datacenter(id: -1, name: "\(location.name)-dc", description: "", location: location)
}
