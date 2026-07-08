import Foundation

/// Shared JSON decoding configuration for all Hetzner API responses.
///
/// `convertFromSnakeCase` is intentionally OFF — model types declare explicit
/// `CodingKeys`. Dates are decoded from ISO8601 strings, trying a
/// fractional-seconds variant first (Hetzner emits both, e.g.
/// "2016-01-30T23:55:00+00:00" and "2016-01-30T23:50:11.560Z"-style values).
func makeHetznerJSONDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()

    decoder.dateDecodingStrategy = .custom { valueDecoder in
        let container = try valueDecoder.singleValueContainer()
        let dateString = try container.decode(String.self)

        // Formatters are created per-call (rather than captured) so the
        // closure stays trivially Sendable — ISO8601DateFormatter isn't.
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractionalSeconds.date(from: dateString) {
            return date
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: dateString) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected an ISO8601 date string, got \"\(dateString)\"."
        )
    }

    return decoder
}

/// Hetzner's error envelope: `{"error": {"code": "...", "message": "..."}}`.
struct HetznerErrorEnvelope: Decodable {
    struct Body: Decodable {
        let code: String
        let message: String
    }
    let error: Body
}
