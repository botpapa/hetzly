import Foundation

/// Robot Webservice failover-IP endpoints (`/failover...`).
///
/// Failover responses use the standard `{"failover": {...}}` wrapper (each
/// list element individually wrapped the same way), so — unlike vSwitch —
/// these calls reuse `RobotDecoding.decodeWrapped`/`decodeWrappedList`.
///
/// Failover routing is live network config (switching it re-points a
/// customer's traffic to a different physical server), so — like vSwitch —
/// none of this goes through the client's 5-minute GET cache: `/failover`
/// is not in `RobotClient.cacheablePathPrefixes`, so every call here always
/// hits the network.
extension RobotClient {
    /// `GET /failover` — wrapped list of every failover IP on the account.
    public func listFailoverIPs() async throws -> [RobotFailover] {
        let data = try await execute(method: .get, path: "/failover")
        return try RobotDecoding.decodeWrappedList(key: "failover", from: data, using: decoder)
    }

    /// `GET /failover/{ip}` — accepts both IPv4 and IPv6 addresses.
    public func failoverIP(ip: String) async throws -> RobotFailover {
        let data = try await execute(method: .get, path: "/failover/\(ip)")
        return try RobotDecoding.decodeWrapped(key: "failover", from: data, using: decoder)
    }

    /// `POST /failover/{ip}` with `active_server_ip=<target>` — switches
    /// routing so traffic to `ip` now reaches `target`. `target` must be
    /// another server's main IP that's already authorized to receive this
    /// failover address (not a server number).
    ///
    /// This is the critical, customer-impacting operation in this file: a
    /// wrong `target` silently reroutes (or black-holes) live traffic, so
    /// this method sends exactly one form field and nothing else — no
    /// implicit retries, no guessing at the caller's intent.
    public func switchFailover(ip: String, to target: String) async throws -> RobotFailover {
        let body = [URLQueryItem(name: "active_server_ip", value: target)]
        let data = try await execute(method: .post, path: "/failover/\(ip)", formBody: body)
        return try RobotDecoding.decodeWrapped(key: "failover", from: data, using: decoder)
    }

    /// `DELETE /failover/{ip}` — disables routing; the returned object has
    /// `activeServerIP == nil`.
    public func deleteFailoverRouting(ip: String) async throws -> RobotFailover {
        let data = try await execute(method: .delete, path: "/failover/\(ip)")
        return try RobotDecoding.decodeWrapped(key: "failover", from: data, using: decoder)
    }
}
