import Foundation

/// Robot Webservice ordering endpoints (`/order/...`). All calls funnel
/// through `RobotClient.execute`, so they share the client's serialization
/// gate and ~150/h budget. Ordering data is intentionally never served from
/// the 5-minute cache: transactions change server-side as orders progress,
/// and market (auction) prices reduce on a timer.
extension RobotClient {
    // MARK: - Products

    /// Standard dedicated server products — `GET /order/server/product`.
    public func listProducts() async throws -> [RobotProduct] {
        let data = try await execute(method: .get, path: "/order/server/product")
        return try RobotDecoding.decodeWrappedList(key: "product", from: data, using: decoder)
    }

    /// One standard product — `GET /order/server/product/{id}`.
    public func product(id: String) async throws -> RobotProduct {
        let data = try await execute(method: .get, path: "/order/server/product/\(id)")
        return try RobotDecoding.decodeWrapped(key: "product", from: data, using: decoder)
    }

    /// Server market (auction) products — `GET /order/server_market/product`.
    public func listMarketProducts() async throws -> [RobotMarketProduct] {
        let data = try await execute(method: .get, path: "/order/server_market/product")
        return try RobotDecoding.decodeWrappedList(key: "product", from: data, using: decoder)
    }

    /// One market product — `GET /order/server_market/product/{id}`.
    public func marketProduct(id: String) async throws -> RobotMarketProduct {
        let data = try await execute(method: .get, path: "/order/server_market/product/\(id)")
        return try RobotDecoding.decodeWrapped(key: "product", from: data, using: decoder)
    }

    // MARK: - Placing orders

    /// Places a standard server order — `POST /order/server` with a
    /// form-encoded body (`product_id`, optional `location`/`dist`, one
    /// `authorized_key[]` per fingerprint, `test`).
    ///
    /// `RobotServerOrder.test` defaults to `true`; Robot then simulates the
    /// order without billing. Callers must explicitly construct the order
    /// with `test: false` to buy a real server. Ordering must be enabled in
    /// Robot's settings — otherwise Robot answers 403 `NOT_ALLOWED`, which
    /// surfaces as `HetznerAPIError.forbidden` with the code in the message.
    public func orderServer(_ order: RobotServerOrder) async throws -> RobotTransaction {
        var form = [URLQueryItem(name: "product_id", value: order.productID)]
        if let location = order.location {
            form.append(URLQueryItem(name: "location", value: location))
        }
        if let dist = order.dist {
            form.append(URLQueryItem(name: "dist", value: dist))
        }
        form.append(contentsOf: order.authorizedKeys.map { URLQueryItem(name: "authorized_key[]", value: $0) })
        form.append(URLQueryItem(name: "test", value: order.test ? "true" : "false"))

        let data = try await execute(method: .post, path: "/order/server", formBody: form)
        return try RobotDecoding.decodeWrapped(key: "transaction", from: data, using: decoder)
    }

    /// Places a server market (auction) order — `POST /order/server_market`.
    /// Market servers are sold as-is, so the body carries only `product_id`,
    /// `authorized_key[]` fingerprints, and `test` (same `test`-defaults-true
    /// safety as `orderServer(_:)`).
    public func orderMarketServer(_ order: RobotMarketOrder) async throws -> RobotTransaction {
        var form = [URLQueryItem(name: "product_id", value: order.productID)]
        form.append(contentsOf: order.authorizedKeys.map { URLQueryItem(name: "authorized_key[]", value: $0) })
        form.append(URLQueryItem(name: "test", value: order.test ? "true" : "false"))

        let data = try await execute(method: .post, path: "/order/server_market", formBody: form)
        return try RobotDecoding.decodeWrapped(key: "transaction", from: data, using: decoder)
    }

    // MARK: - Transactions

    /// All order transactions — merges `GET /order/server/transaction` and
    /// `GET /order/server_market/transaction`, sorted by date descending
    /// (newest first). Robot answers 404 when an account has no transactions
    /// at all; that is treated as an empty list, not an error.
    public func listTransactions() async throws -> [RobotTransaction] {
        let standard = try await transactionsToleratingNotFound(path: "/order/server/transaction")
        let market = try await transactionsToleratingNotFound(path: "/order/server_market/transaction")
        return (standard + market).sorted { lhs, rhs in
            let lhsDate = lhs.dateValue ?? .distantPast
            let rhsDate = rhs.dateValue ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.id > rhs.id
        }
    }

    /// One transaction by ID — tries `GET /order/server/transaction/{id}`
    /// first, and on 404 falls back to the market transaction endpoint
    /// (`GET /order/server_market/transaction/{id}`).
    public func transaction(id: String) async throws -> RobotTransaction {
        do {
            let data = try await execute(method: .get, path: "/order/server/transaction/\(id)")
            return try RobotDecoding.decodeWrapped(key: "transaction", from: data, using: decoder)
        } catch HetznerAPIError.notFound {
            let data = try await execute(method: .get, path: "/order/server_market/transaction/\(id)")
            return try RobotDecoding.decodeWrapped(key: "transaction", from: data, using: decoder)
        }
    }

    private func transactionsToleratingNotFound(path: String) async throws -> [RobotTransaction] {
        do {
            let data = try await execute(method: .get, path: path)
            return try RobotDecoding.decodeWrappedList(key: "transaction", from: data, using: decoder)
        } catch HetznerAPIError.notFound {
            return []
        }
    }
}
