import Foundation

/// Transparently walks Hetzner's `page` / `per_page` pagination, yielding one
/// array of `T` per page until `meta.pagination.next_page` is `null`.
public func paginated<T: Decodable & Sendable>(
    client: HetznerHTTPClient,
    endpoint: Endpoint,
    itemsKey: String,
    perPage: Int
) -> AsyncThrowingStream<[T], Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                var page = 1
                while true {
                    var pageEndpoint = endpoint
                    var query = endpoint.query.filter { $0.name != "page" && $0.name != "per_page" }
                    query.append(URLQueryItem(name: "page", value: String(page)))
                    query.append(URLQueryItem(name: "per_page", value: String(perPage)))
                    pageEndpoint.query = query

                    let data = try await client.fetchPageData(pageEndpoint)

                    let decoder = makeHetznerJSONDecoder()
                    decoder.userInfo[PaginationUserInfoKey.itemsKey] = itemsKey

                    let envelope: PaginatedEnvelope<T>
                    do {
                        envelope = try decoder.decode(PaginatedEnvelope<T>.self, from: data)
                    } catch {
                        throw HetznerAPIError.decoding(underlying: String(describing: error))
                    }

                    continuation.yield(envelope.items)

                    guard let nextPage = envelope.meta?.pagination.nextPage else {
                        continuation.finish()
                        return
                    }
                    page = nextPage
                }
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

// MARK: - Envelope decoding

enum PaginationUserInfoKey {
    static let itemsKey = CodingUserInfoKey(rawValue: "com.hetznerkit.itemsKey")!
}

struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }

    init(named name: String) {
        self.stringValue = name
        self.intValue = nil
    }
}

struct PaginationMeta: Decodable {
    struct Pagination: Decodable {
        let page: Int
        let perPage: Int
        let previousPage: Int?
        let nextPage: Int?
        let lastPage: Int?
        let totalEntries: Int?

        enum CodingKeys: String, CodingKey {
            case page
            case perPage = "per_page"
            case previousPage = "previous_page"
            case nextPage = "next_page"
            case lastPage = "last_page"
            case totalEntries = "total_entries"
        }
    }

    let pagination: Pagination
}

struct PaginatedEnvelope<T: Decodable>: Decodable {
    let items: [T]
    let meta: PaginationMeta?

    init(from decoder: Decoder) throws {
        guard let itemsKeyValue = decoder.userInfo[PaginationUserInfoKey.itemsKey] as? String else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Missing itemsKey in decoder userInfo for pagination."
                )
            )
        }

        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let itemsCodingKey = DynamicCodingKey(named: itemsKeyValue)
        items = try container.decode([T].self, forKey: itemsCodingKey)
        meta = try container.decodeIfPresent(PaginationMeta.self, forKey: DynamicCodingKey(named: "meta"))
    }
}
