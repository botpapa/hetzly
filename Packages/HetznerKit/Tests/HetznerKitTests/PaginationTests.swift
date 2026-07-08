import Foundation
import Testing
@testable import HetznerKit

private struct ServerStub: Decodable, Sendable, Equatable {
    let id: Int
}

private func pageData(itemIDs: [Int], nextPage: Int?) -> Data {
    let nextString = nextPage.map(String.init) ?? "null"
    let items = itemIDs.map { "{\"id\":\($0)}" }.joined(separator: ",")
    let json = """
    {"servers":[\(items)],"meta":{"pagination":{"page":1,"per_page":2,"previous_page":null,"next_page":\(nextString),"last_page":3,"total_entries":5}}}
    """
    return Data(json.utf8)
}

@Suite("Pagination")
struct PaginationTests {
    @Test func walksAllPagesAndStopsAtNilNextPage() async throws {
        let transport = MockTransport(responses: [
            .init(statusCode: 200, data: pageData(itemIDs: [1], nextPage: 2)),
            .init(statusCode: 200, data: pageData(itemIDs: [2, 3], nextPage: 3)),
            .init(statusCode: 200, data: pageData(itemIDs: [4, 5], nextPage: nil)),
        ])
        let configuration = APIConfiguration(
            baseURL: URL(string: "https://api.hetzner.cloud/v1")!,
            auth: .bearer(token: "t")
        )
        let client = HetznerHTTPClient(
            configuration: configuration,
            transport: transport,
            rateLimiter: RateLimiter(budget: 1000, window: 60)
        )

        let stream: AsyncThrowingStream<[ServerStub], Error> = paginated(
            client: client,
            endpoint: Endpoint(path: "/servers"),
            itemsKey: "servers",
            perPage: 2
        )

        var allIDs: [Int] = []
        for try await page in stream {
            allIDs.append(contentsOf: page.map(\.id))
        }

        #expect(allIDs == [1, 2, 3, 4, 5])

        let requests = await transport.recordedRequests
        #expect(requests.count == 3)
        #expect(requests[0].url?.query?.contains("page=1") == true)
        #expect(requests[1].url?.query?.contains("page=2") == true)
        #expect(requests[2].url?.query?.contains("page=3") == true)
    }

    @Test func singlePageStreamStopsImmediately() async throws {
        let transport = MockTransport(responses: [
            .init(statusCode: 200, data: pageData(itemIDs: [1], nextPage: nil)),
        ])
        let configuration = APIConfiguration(
            baseURL: URL(string: "https://api.hetzner.cloud/v1")!,
            auth: .bearer(token: "t")
        )
        let client = HetznerHTTPClient(
            configuration: configuration,
            transport: transport,
            rateLimiter: RateLimiter(budget: 1000, window: 60)
        )

        let stream: AsyncThrowingStream<[ServerStub], Error> = paginated(
            client: client,
            endpoint: Endpoint(path: "/servers"),
            itemsKey: "servers",
            perPage: 2
        )

        var pages = 0
        for try await _ in stream {
            pages += 1
        }
        #expect(pages == 1)
    }
}
