import Foundation
import Testing
@testable import HetznerKit

/// Fixtures local to this file.
private enum OrderingFixtures {
    static func productJSON(
        id: String = "EX44",
        dist: String = "[\"Rescue system\", \"Debian 12\"]",
        location: String = "[\"FSN1\", \"HEL1\"]"
    ) -> String {
        """
        {
            "id": "\(id)",
            "name": "EX44",
            "description": ["Intel Core i5", "64 GB DDR4", "2x 512 GB NVMe SSD"],
            "traffic": "unlimited",
            "dist": \(dist),
            "arch": ["64"],
            "lang": ["en", "de"],
            "location": \(location),
            "prices": [
                {
                    "location": "FSN1",
                    "price": {"net": "39.0000", "gross": "46.4100"},
                    "price_setup": {"net": "0.0000", "gross": "0.0000"},
                    "price_hourly": {"net": "0.0600", "gross": "0.0714"}
                }
            ]
        }
        """
    }

    static func productEnvelopeJSON(id: String = "EX44") -> Data {
        Data("{\"product\": \(productJSON(id: id))}".utf8)
    }

    static func productsListJSON(ids: [String]) -> Data {
        let items = ids.map { "{\"product\": \(productJSON(id: $0))}" }.joined(separator: ",")
        return Data("[\(items)]".utf8)
    }

    static func marketProductJSON(id: String = "2809759", includeOptionalFields: Bool = true) -> String {
        let optional = includeOptionalFields ? """
        ,
            "cpu_benchmark": 4500,
            "hdd_text": "2x 1 TB SATA",
            "hdd_count": 2,
            "datacenter": "FSN1-DC5",
            "network_speed": "1 GBit",
            "price_vat": "46.41",
            "next_reduce": 3600,
            "next_reduce_date": "2026-07-09"
        """ : ""
        return """
        {
            "id": \(id),
            "name": "AX41-NVMe",
            "description": ["AMD Ryzen 5 3600", "64 GB DDR4"],
            "traffic": "unlimited",
            "dist": "Rescue system",
            "cpu": "AMD Ryzen 5 3600",
            "memory_size": 64,
            "hdd_size": 1000,
            "price": "39.0000",
            "price_setup": "0.0000",
            "fixed_price": true\(optional)
        }
        """
    }

    static func marketProductEnvelopeJSON(id: String = "2809759", includeOptionalFields: Bool = true) -> Data {
        Data("{\"product\": \(marketProductJSON(id: id, includeOptionalFields: includeOptionalFields))}".utf8)
    }

    static func transactionJSON(
        id: String = "B20150121123456",
        date: String = "2026-07-01 12:00:00",
        status: String = "in process",
        serverNumber: Int? = 12345,
        authorizedKey: String? = """
        [{"key": {"name": "my-key", "fingerprint": "38:59:...:15:c3"}}]
        """
    ) -> String {
        let serverNumberValue = serverNumber.map(String.init) ?? "null"
        let keyValue = authorizedKey ?? "null"
        return """
        {
            "id": "\(id)",
            "date": "\(date)",
            "status": "\(status)",
            "server_number": \(serverNumberValue),
            "server_ip": null,
            "authorized_key": \(keyValue),
            "product": {"id": "EX44", "name": "EX44", "description": ["Intel Core i5"]},
            "comment": null
        }
        """
    }

    static func transactionEnvelopeJSON(id: String = "B20150121123456") -> Data {
        Data("{\"transaction\": \(transactionJSON(id: id))}".utf8)
    }

    static func forbiddenNotAllowedJSON() -> Data {
        Data("""
        {"error": {"status": 403, "code": "NOT_ALLOWED", "message": "ordering is not enabled for this account"}}
        """.utf8)
    }
}

@Suite("RobotAPI Ordering — models")
struct RobotAPIOrderingModelTests {
    private let decoder = JSONDecoder()

    @Test func productDecodesWrappedEnvelope() throws {
        let envelope = try decoder.decode(RobotProductEnvelope.self, from: OrderingFixtures.productEnvelopeJSON())
        let product = envelope.product
        #expect(product.id == "EX44")
        #expect(product.name == "EX44")
        #expect(product.traffic == "unlimited")
        #expect(product.description.count == 3)
    }

    @Test func productListDecodesEachWrappedElement() throws {
        let data = OrderingFixtures.productsListJSON(ids: ["EX44", "EX101"])
        let envelopes = try decoder.decode([RobotProductEnvelope].self, from: data)
        #expect(envelopes.map(\.product.id) == ["EX44", "EX101"])
    }

    @Test func productDistToleratesArrayShape() throws {
        let json = "{\"product\": \(OrderingFixtures.productJSON(dist: "[\"Rescue system\", \"Debian 12\"]"))}"
        let envelope = try decoder.decode(RobotProductEnvelope.self, from: Data(json.utf8))
        #expect(envelope.product.dist == ["Rescue system", "Debian 12"])
    }

    @Test func productDistToleratesSingleStringShape() throws {
        let json = "{\"product\": \(OrderingFixtures.productJSON(dist: "\"Rescue system\""))}"
        let envelope = try decoder.decode(RobotProductEnvelope.self, from: Data(json.utf8))
        #expect(envelope.product.dist == ["Rescue system"])
    }

    @Test func productLocationToleratesSingleStringShape() throws {
        let json = "{\"product\": \(OrderingFixtures.productJSON(location: "\"FSN1\""))}"
        let envelope = try decoder.decode(RobotProductEnvelope.self, from: Data(json.utf8))
        #expect(envelope.product.location == ["FSN1"])
    }

    @Test func productPriceDecimalAccessorsParseNetAndGross() throws {
        let envelope = try decoder.decode(RobotProductEnvelope.self, from: OrderingFixtures.productEnvelopeJSON())
        let price = try #require(envelope.product.prices.first)
        #expect(price.price.netDecimal == Decimal(string: "39.0000"))
        #expect(price.price.grossDecimal == Decimal(string: "46.4100"))
        #expect(price.priceHourly?.netDecimal == Decimal(string: "0.0600"))
    }

    @Test func marketProductDecodesAuctionFields() throws {
        let envelope = try decoder.decode(RobotMarketProductEnvelope.self, from: OrderingFixtures.marketProductEnvelopeJSON())
        let product = envelope.product
        #expect(product.id == "2809759")
        #expect(product.cpu == "AMD Ryzen 5 3600")
        #expect(product.memorySize == 64)
        #expect(product.hddSize == 1000)
        #expect(product.hddText == "2x 1 TB SATA")
        #expect(product.fixedPrice == true)
        #expect(product.priceDecimal == Decimal(string: "39.0000"))
        #expect(product.priceSetupDecimal == Decimal(string: "0.0000"))
        #expect(product.nextReduce == 3600)
    }

    @Test func marketProductDecodesDefensivelyWhenOptionalFieldsMissing() throws {
        let data = OrderingFixtures.marketProductEnvelopeJSON(includeOptionalFields: false)
        let envelope = try decoder.decode(RobotMarketProductEnvelope.self, from: data)
        let product = envelope.product
        #expect(product.id == "2809759")
        #expect(product.cpuBenchmark == nil)
        #expect(product.hddText == nil)
        #expect(product.datacenter == nil)
        #expect(product.nextReduce == nil)
    }

    @Test func transactionDecodesStatusAndWrappedAuthorizedKeys() throws {
        let envelope = try decoder.decode(RobotTransactionEnvelope.self, from: OrderingFixtures.transactionEnvelopeJSON())
        let transaction = envelope.transaction
        #expect(transaction.id == "B20150121123456")
        #expect(transaction.status == .inProcess)
        #expect(transaction.serverNumber == 12345)
        #expect(transaction.product?.id == "EX44")
        let keys = try #require(transaction.authorizedKeys)
        #expect(keys.first?.name == "my-key")
        #expect(keys.first?.fingerprint == "38:59:...:15:c3")
    }

    @Test func transactionStatusDecodesReadyAndCancelledAndUnknown() throws {
        for (raw, expected) in [("ready", RobotTransactionStatus.ready), ("cancelled", .cancelled), ("something_new", .unknown)] {
            let json = OrderingFixtures.transactionJSON(status: raw)
            let transaction = try decoder.decode(RobotTransaction.self, from: Data(json.utf8))
            #expect(transaction.status == expected)
        }
    }

    @Test func transactionDateValueParsesMySQLStyleTimestamp() throws {
        let transaction = try decoder.decode(RobotTransaction.self, from: Data(OrderingFixtures.transactionJSON(date: "2026-07-01 12:00:00").utf8))
        let date = try #require(transaction.dateValue)
        let components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
        #expect(components.year == 2026)
        #expect(components.month == 7)
        #expect(components.day == 1)
    }

    @Test func transactionToleratesMissingAuthorizedKeys() throws {
        let json = OrderingFixtures.transactionJSON(authorizedKey: nil)
        let transaction = try decoder.decode(RobotTransaction.self, from: Data(json.utf8))
        #expect(transaction.authorizedKeys == nil)
    }

    @Test func serverOrderDefaultsTestToTrue() {
        let order = RobotServerOrder(productID: "EX44", authorizedKeys: ["ab:cd"])
        #expect(order.test == true)
    }

    @Test func marketOrderDefaultsTestToTrue() {
        let order = RobotMarketOrder(productID: "2809759", authorizedKeys: ["ab:cd"])
        #expect(order.test == true)
    }

    @Test func serverOrderCanExplicitlyDisableTestMode() {
        let order = RobotServerOrder(productID: "EX44", test: false)
        #expect(order.test == false)
    }
}

@Suite("RobotAPI Ordering — client")
struct RobotAPIOrderingClientTests {
    private func makeClient(responses: [MockTransport.ScriptedResponse]) -> (RobotClient, MockTransport) {
        let transport = MockTransport(responses: responses)
        let client = RobotClient(username: "user", password: "pass", transport: transport)
        return (client, transport)
    }

    /// Decodes a form-urlencoded body into ordered (name, value) pairs.
    private func formPairs(_ request: URLRequest) throws -> [(String, String)] {
        let data = try #require(request.httpBody)
        let body = try #require(String(data: data, encoding: .utf8))
        return body.split(separator: "&").map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = String(parts[0]).removingPercentEncoding ?? String(parts[0])
            let value = parts.count > 1 ? (String(parts[1]).removingPercentEncoding ?? String(parts[1])) : ""
            return (name, value)
        }
    }

    @Test func listProductsHitsProductPathAndDecodesWrappedList() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: OrderingFixtures.productsListJSON(ids: ["EX44", "AX102"])),
        ])

        let products = try await client.listProducts()
        #expect(products.map(\.id) == ["EX44", "AX102"])

        let requests = await transport.recordedRequests
        #expect(requests.count == 1)
        #expect(requests[0].url?.absoluteString == "https://robot-ws.your-server.de/order/server/product")
        #expect(requests[0].httpMethod == "GET")
    }

    @Test func productFetchesSingleByID() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: OrderingFixtures.productEnvelopeJSON(id: "EX101")),
        ])

        let product = try await client.product(id: "EX101")
        #expect(product.id == "EX101")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://robot-ws.your-server.de/order/server/product/EX101")
    }

    @Test func listMarketProductsHitsMarketPath() async throws {
        let envelope = try #require(String(data: OrderingFixtures.marketProductEnvelopeJSON(), encoding: .utf8))
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: Data("[\(envelope)]".utf8)),
        ])

        let products = try await client.listMarketProducts()
        #expect(products.map(\.id) == ["2809759"])

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://robot-ws.your-server.de/order/server_market/product")
    }

    @Test func marketProductFetchesSingleByID() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: OrderingFixtures.marketProductEnvelopeJSON(id: "999")),
        ])

        let product = try await client.marketProduct(id: "999")
        #expect(product.id == "999")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://robot-ws.your-server.de/order/server_market/product/999")
    }

    @Test func orderServerSendsExactFormBodyWithTestDefaultTrue() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: OrderingFixtures.transactionEnvelopeJSON()),
        ])

        let order = RobotServerOrder(
            productID: "EX44",
            location: "FSN1",
            dist: "Debian 12",
            authorizedKeys: ["ab:cd:ef", "12:34:56"]
        )
        let transaction = try await client.orderServer(order)
        #expect(transaction.id == "B20150121123456")
        #expect(transaction.status == .inProcess)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://robot-ws.your-server.de/order/server")
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[0].value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")

        let pairs = try formPairs(requests[0])
        #expect(pairs.map(\.0) == ["product_id", "location", "dist", "authorized_key[]", "authorized_key[]", "test"])
        #expect(pairs.map(\.1) == ["EX44", "FSN1", "Debian 12", "ab:cd:ef", "12:34:56", "true"])
    }

    @Test func orderServerSendsTestFalseOnlyWhenExplicitlySet() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: OrderingFixtures.transactionEnvelopeJSON()),
        ])

        _ = try await client.orderServer(RobotServerOrder(productID: "EX44", test: false))

        let requests = await transport.recordedRequests
        let pairs = try formPairs(requests[0])
        #expect(pairs.map(\.0) == ["product_id", "test"])
        #expect(pairs.map(\.1) == ["EX44", "false"])
    }

    @Test func orderMarketServerSendsProductKeysAndTestOnly() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: OrderingFixtures.transactionEnvelopeJSON(id: "M2026")),
        ])

        let transaction = try await client.orderMarketServer(
            RobotMarketOrder(productID: "2809759", authorizedKeys: ["ab:cd:ef"])
        )
        #expect(transaction.id == "M2026")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://robot-ws.your-server.de/order/server_market")
        #expect(requests[0].httpMethod == "POST")

        let pairs = try formPairs(requests[0])
        #expect(pairs.map(\.0) == ["product_id", "authorized_key[]", "test"])
        #expect(pairs.map(\.1) == ["2809759", "ab:cd:ef", "true"])
    }

    @Test func listTransactionsMergesBothEndpointsSortedByDateDescending() async throws {
        let older = OrderingFixtures.transactionJSON(id: "OLD1", date: "2026-06-01 08:00:00")
        let newest = OrderingFixtures.transactionJSON(id: "NEW1", date: "2026-07-02 09:30:00")
        let middle = OrderingFixtures.transactionJSON(id: "MID1", date: "2026-06-15 10:00:00")

        let standardList = Data("[{\"transaction\": \(older)}, {\"transaction\": \(newest)}]".utf8)
        let marketList = Data("[{\"transaction\": \(middle)}]".utf8)

        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: standardList),
            .init(statusCode: 200, data: marketList),
        ])

        let transactions = try await client.listTransactions()
        #expect(transactions.map(\.id) == ["NEW1", "MID1", "OLD1"])

        let requests = await transport.recordedRequests
        #expect(requests.count == 2)
        #expect(requests[0].url?.absoluteString == "https://robot-ws.your-server.de/order/server/transaction")
        #expect(requests[1].url?.absoluteString == "https://robot-ws.your-server.de/order/server_market/transaction")
    }

    @Test func listTransactionsTreats404AsEmptyList() async throws {
        let notFound = Data("""
        {"error": {"status": 404, "code": "NOT_FOUND", "message": "no transactions found"}}
        """.utf8)
        let marketOnly = Data("[{\"transaction\": \(OrderingFixtures.transactionJSON(id: "M1"))}]".utf8)

        let (client, _) = makeClient(responses: [
            .init(statusCode: 404, data: notFound),
            .init(statusCode: 200, data: marketOnly),
        ])

        let transactions = try await client.listTransactions()
        #expect(transactions.map(\.id) == ["M1"])
    }

    @Test func listTransactionsIsEmptyWhenBothEndpointsReturn404() async throws {
        let notFound = Data("""
        {"error": {"status": 404, "code": "NOT_FOUND", "message": "no transactions found"}}
        """.utf8)

        let (client, _) = makeClient(responses: [
            .init(statusCode: 404, data: notFound),
            .init(statusCode: 404, data: notFound),
        ])

        let transactions = try await client.listTransactions()
        #expect(transactions.isEmpty)
    }

    @Test func transactionFallsBackToMarketEndpointOn404() async throws {
        let notFound = Data("""
        {"error": {"status": 404, "code": "TRANSACTION_NOT_FOUND", "message": "transaction not found"}}
        """.utf8)

        let (client, transport) = makeClient(responses: [
            .init(statusCode: 404, data: notFound),
            .init(statusCode: 200, data: OrderingFixtures.transactionEnvelopeJSON(id: "MKT77")),
        ])

        let transaction = try await client.transaction(id: "MKT77")
        #expect(transaction.id == "MKT77")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://robot-ws.your-server.de/order/server/transaction/MKT77")
        #expect(requests[1].url?.absoluteString == "https://robot-ws.your-server.de/order/server_market/transaction/MKT77")
    }

    @Test func orderingDisabled403SurfacesAsForbiddenWithCodeInMessage() async throws {
        let (client, _) = makeClient(responses: [
            .init(statusCode: 403, data: OrderingFixtures.forbiddenNotAllowedJSON()),
        ])

        do {
            _ = try await client.orderServer(RobotServerOrder(productID: "EX44"))
            Issue.record("Expected HetznerAPIError.forbidden to be thrown")
        } catch HetznerAPIError.forbidden(let message) {
            let text = try #require(message)
            #expect(text.contains("NOT_ALLOWED"))
            #expect(text.contains("ordering is not enabled"))
        }
    }
}
