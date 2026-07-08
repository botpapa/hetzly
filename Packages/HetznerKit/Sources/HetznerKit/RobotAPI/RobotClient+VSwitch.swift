import Foundation

/// Robot Webservice vSwitch endpoints (`/vswitch...`).
///
/// Unlike every other resource in this client, vSwitch responses are **not**
/// wrapped in Robot's usual `{"resource": {...}}` envelope: `GET /vswitch`
/// answers with a plain JSON array of vSwitch objects, and
/// `GET /vswitch/{id}` / `POST /vswitch` / `POST /vswitch/{id}` all answer
/// with a plain (unwrapped) vSwitch object. This was confirmed against
/// Robot's real wire format (a `#[derive(Deserialize)]` struct with a
/// passing round-trip test in a maintained third-party client, since the
/// prose docs describe the shape but don't show it byte-for-byte) — see
/// `RobotAPIVSwitchFailoverTests.swift` for the fixtures. `RobotDecoding`'s
/// `decodeWrapped`/`decodeWrappedList` are therefore intentionally NOT used
/// here; `decodeRobotVSwitch`/`decodeRobotVSwitchList` below decode directly.
///
/// vSwitch config is mutable infrastructure state (connecting a server is an
/// async, multi-second operation on Robot's side), so none of these calls
/// read from or write to the client's 5-minute GET cache — `/vswitch` is
/// deliberately absent from `RobotClient.cacheablePathPrefixes`, so every
/// call here always hits the network.
extension RobotClient {
    // MARK: - Reading

    /// `GET /vswitch` — plain JSON array, list shape (no connected
    /// servers/subnets/cloud networks; `RobotVSwitch`'s decoder defaults
    /// those to `[]`).
    public func listVSwitches() async throws -> [RobotVSwitch] {
        let data = try await execute(method: .get, path: "/vswitch")
        return try decodeRobotVSwitchList(data)
    }

    /// `GET /vswitch/{id}` — plain JSON object, detail shape (populated
    /// `servers`/`subnets`/`cloudNetworks`).
    public func vSwitch(id: Int) async throws -> RobotVSwitch {
        let data = try await execute(method: .get, path: "/vswitch/\(id)")
        return try decodeRobotVSwitch(data)
    }

    // MARK: - Writing

    /// `POST /vswitch` with `name`/`vlan` form fields. Succeeds with
    /// `201 Created`; the response is the new vSwitch in list shape (it has
    /// no connected servers/subnets/cloud networks yet).
    public func createVSwitch(name: String, vlan: Int) async throws -> RobotVSwitch {
        let body = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "vlan", value: String(vlan)),
        ]
        let data = try await execute(method: .post, path: "/vswitch", formBody: body)
        return try decodeRobotVSwitch(data)
    }

    /// `POST /vswitch/{id}` — renames and/or re-VLANs an existing vSwitch.
    /// Robot's update endpoint takes both `name` and `vlan` together (there
    /// is no partial-update form), so callers pass the full desired state.
    public func updateVSwitch(id: Int, name: String, vlan: Int) async throws -> RobotVSwitch {
        let body = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "vlan", value: String(vlan)),
        ]
        let data = try await execute(method: .post, path: "/vswitch/\(id)", formBody: body)
        return try decodeRobotVSwitch(data)
    }

    /// `DELETE /vswitch/{id}` with a form-encoded (not query-string)
    /// `cancellation_date`. Pass `nil` for immediate cancellation — this
    /// sends `cancellation_date=now`, matching Robot's documented sentinel
    /// value; pass a `"yyyy-MM-dd"` string to schedule cancellation for a
    /// future date instead.
    public func deleteVSwitch(id: Int, cancellationDate: String? = nil) async throws {
        let body = [URLQueryItem(name: "cancellation_date", value: cancellationDate ?? "now")]
        _ = try await execute(method: .delete, path: "/vswitch/\(id)", formBody: body)
    }

    /// `POST /vswitch/{id}/server` — connects one or more dedicated servers
    /// to the vSwitch. Robot's array-form encoding repeats the same key
    /// once per value (`server[]=1&server[]=2&...`), matching
    /// `authorized_key[]` elsewhere in this client. Connecting is
    /// asynchronous on Robot's side — poll `vSwitch(id:)` and watch
    /// `servers[].status` for `.ready`.
    public func addVSwitchServers(id: Int, serverNumbers: [Int]) async throws {
        let body = serverNumbers.map { URLQueryItem(name: "server[]", value: String($0)) }
        _ = try await execute(method: .post, path: "/vswitch/\(id)/server", formBody: body)
    }

    /// `DELETE /vswitch/{id}/server` — disconnects one or more servers,
    /// using the same repeated `server[]` form encoding as
    /// `addVSwitchServers`.
    public func removeVSwitchServers(id: Int, serverNumbers: [Int]) async throws {
        let body = serverNumbers.map { URLQueryItem(name: "server[]", value: String($0)) }
        _ = try await execute(method: .delete, path: "/vswitch/\(id)/server", formBody: body)
    }

    // MARK: - Plain (unwrapped) decoding

    private func decodeRobotVSwitch(_ data: Data) throws -> RobotVSwitch {
        do {
            return try decoder.decode(RobotVSwitch.self, from: data)
        } catch {
            throw HetznerAPIError.decoding(underlying: String(describing: error))
        }
    }

    private func decodeRobotVSwitchList(_ data: Data) throws -> [RobotVSwitch] {
        do {
            return try decoder.decode([RobotVSwitch].self, from: data)
        } catch {
            throw HetznerAPIError.decoding(underlying: String(describing: error))
        }
    }
}
