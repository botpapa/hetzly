import Foundation

/// Image catalog operations: listing (with optional type filter), fetching,
/// deleting, and updating metadata/protection.
extension CloudClient {
    /// All images, fully paginated, optionally filtered to a single
    /// `type` (e.g. `.snapshot`), newest first.
    public func listImages(type: ImageType? = nil) async throws -> [Image] {
        var query = [URLQueryItem(name: "sort", value: "created:desc")]
        if let type {
            query.append(URLQueryItem(name: "type", value: type.rawValue))
        }

        let stream: AsyncThrowingStream<[Image], Error> = paginated(
            client: client,
            endpoint: Endpoint(path: "/images", query: query),
            itemsKey: "images",
            perPage: 50
        )

        var images: [Image] = []
        for try await page in stream {
            images.append(contentsOf: page)
        }
        return images
    }

    public func image(id: Int) async throws -> Image {
        let envelope: ImageEnvelope = try await client.send(Endpoint(path: "/images/\(id)"))
        return envelope.image
    }

    public func deleteImage(id: Int) async throws {
        try await client.sendExpectingNoContent(Endpoint(method: .delete, path: "/images/\(id)"))
    }

    /// Updates description and/or labels. Fields left `nil` are omitted from
    /// the request and unchanged server-side.
    public func updateImage(id: Int, description: String? = nil, labels: [String: String]? = nil) async throws -> Image {
        let body = try JSONEncoder().encode(UpdateImageRequest(description: description, labels: labels))
        let endpoint = Endpoint(method: .put, path: "/images/\(id)", body: body)
        let envelope: ImageEnvelope = try await client.send(endpoint)
        return envelope.image
    }

    public func changeImageProtection(id: Int, delete: Bool) async throws -> Action {
        let body = try JSONEncoder().encode(ChangeImageProtectionRequest(delete: delete))
        let endpoint = Endpoint(method: .post, path: "/images/\(id)/actions/change_protection", body: body)
        let envelope: ActionEnvelope = try await client.send(endpoint)
        return envelope.action
    }
}

// MARK: - Request bodies

private struct UpdateImageRequest: Encodable {
    let description: String?
    let labels: [String: String]?
}

private struct ChangeImageProtectionRequest: Encodable {
    let delete: Bool
}
