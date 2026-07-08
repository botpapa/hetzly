import Foundation

/// Read-only reference/catalog data: server types, locations, datacenters,
/// and ISOs. All fully paginated.
extension CloudClient {
    public func listServerTypes() async throws -> [ServerType] {
        try await collectAllPages(path: "/server_types", itemsKey: "server_types")
    }

    public func listLocations() async throws -> [Location] {
        try await collectAllPages(path: "/locations", itemsKey: "locations")
    }

    public func listDatacenters() async throws -> [Datacenter] {
        try await collectAllPages(path: "/datacenters", itemsKey: "datacenters")
    }

    public func listISOs() async throws -> [ISO] {
        try await collectAllPages(path: "/isos", itemsKey: "isos")
    }

    private func collectAllPages<T: Decodable & Sendable>(path: String, itemsKey: String) async throws -> [T] {
        let stream: AsyncThrowingStream<[T], Error> = paginated(
            client: client,
            endpoint: Endpoint(path: path),
            itemsKey: itemsKey,
            perPage: 50
        )

        var items: [T] = []
        for try await page in stream {
            items.append(contentsOf: page)
        }
        return items
    }
}
