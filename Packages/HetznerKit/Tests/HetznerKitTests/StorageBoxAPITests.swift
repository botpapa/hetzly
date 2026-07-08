import Foundation
import Testing
@testable import HetznerKit

/// Fixtures local to this file — synthetic values shaped to match the
/// documented Storage Box API wire format (see StorageBoxAPI source
/// headers for citation of sources used).
private enum StorageBoxFixtures {
    static let locationJSON = """
    {
        "id": 1,
        "name": "fsn1",
        "description": "Falkenstein DC Park 1",
        "country": "DE",
        "city": "Falkenstein",
        "latitude": 50.47612,
        "longitude": 12.370071,
        "network_zone": "eu-central"
    }
    """

    static let storageBoxTypeJSON = """
    {
        "id": 10,
        "name": "bx11",
        "description": "BX11",
        "snapshot_limit": 10,
        "automatic_snapshot_limit": 10,
        "subaccounts_limit": 200,
        "size": 1073741824000,
        "prices": [
            {
                "location": "fsn1",
                "price_hourly": {"net": "0.0060", "gross": "0.0071"},
                "price_monthly": {"net": "3.90", "gross": "4.64"},
                "setup_fee": {"net": "0.00", "gross": "0.00"}
            }
        ],
        "deprecation": null
    }
    """

    static func accessSettingsJSON(
        reachable: Bool = true,
        samba: Bool = false,
        ssh: Bool = true,
        webdav: Bool = false,
        zfs: Bool = false
    ) -> String {
        """
        {
            "reachable_externally": \(reachable),
            "samba_enabled": \(samba),
            "ssh_enabled": \(ssh),
            "webdav_enabled": \(webdav),
            "zfs_enabled": \(zfs)
        }
        """
    }

    static func storageBoxJSON(id: Int = 100, name: String = "backups", status: String = "active") -> String {
        """
        {
            "id": \(id),
            "username": "u\(id)",
            "status": "\(status)",
            "name": "\(name)",
            "storage_box_type": \(storageBoxTypeJSON),
            "location": \(locationJSON),
            "access_settings": \(accessSettingsJSON()),
            "server": "u\(id).your-storagebox.de",
            "system": "FSN1-BX11",
            "stats": {"size": 1000, "size_data": 800, "size_snapshots": 200},
            "labels": {"env": "prod"},
            "protection": {"delete": false},
            "snapshot_plan": null,
            "created": "2025-06-25T10:00:00+00:00"
        }
        """
    }

    static func storageBoxEnvelopeJSON(id: Int = 100, name: String = "backups") -> Data {
        Data("{\"storage_box\": \(storageBoxJSON(id: id, name: name))}".utf8)
    }

    static func storageBoxesPageJSON(boxes: [(id: Int, name: String)], nextPage: Int?) -> Data {
        let items = boxes.map { storageBoxJSON(id: $0.id, name: $0.name) }.joined(separator: ",")
        let nextString = nextPage.map(String.init) ?? "null"
        let json = """
        {
            "storage_boxes": [\(items)],
            "meta": {
                "pagination": {
                    "page": 1, "per_page": 50, "previous_page": null,
                    "next_page": \(nextString), "last_page": 2, "total_entries": \(boxes.count)
                }
            }
        }
        """
        return Data(json.utf8)
    }

    static func actionJSON(command: String) -> String {
        """
        {"id": 1, "command": "\(command)", "status": "running", "progress": 0, "started": "2025-06-25T10:00:00+00:00", "finished": null, "resources": [], "error": null}
        """
    }

    static func actionEnvelopeJSON(command: String) -> Data {
        Data("{\"action\": \(actionJSON(command: command))}".utf8)
    }

    static func snapshotJSON(id: Int = 1, name: String = "snap-1", storageBoxID: Int = 100, isAutomatic: Bool = false) -> String {
        """
        {
            "id": \(id),
            "name": "\(name)",
            "description": "manual backup",
            "stats": {"size": 500, "size_filesystem": 600},
            "is_automatic": \(isAutomatic),
            "labels": {},
            "created": "2025-07-01T08:00:00+00:00",
            "storage_box": \(storageBoxID)
        }
        """
    }

    static func snapshotEnvelopeJSON(id: Int = 1) -> Data {
        Data("{\"snapshot\": \(snapshotJSON(id: id))}".utf8)
    }

    static func snapshotCreateResponseJSON(id: Int = 1) -> Data {
        Data("{\"snapshot\": \(snapshotJSON(id: id)), \"action\": \(actionJSON(command: "create_snapshot"))}".utf8)
    }

    static func snapshotsPageJSON(ids: [Int]) -> Data {
        let items = ids.map { snapshotJSON(id: $0) }.joined(separator: ",")
        return Data("{\"snapshots\": [\(items)]}".utf8)
    }

    static func subaccountJSON(id: Int = 1, username: String = "sub1", storageBoxID: Int = 100) -> String {
        """
        {
            "id": \(id),
            "name": "worker",
            "username": "\(username)",
            "home_directory": "/backups",
            "server": "u100-sub1.your-storagebox.de",
            "access_settings": {
                "reachable_externally": true,
                "readonly": false,
                "samba_enabled": false,
                "ssh_enabled": true,
                "webdav_enabled": false
            },
            "description": "ci uploader",
            "labels": {},
            "created": "2025-07-02T09:00:00+00:00",
            "storage_box": \(storageBoxID)
        }
        """
    }

    static func subaccountCreateResponseJSON(id: Int = 1) -> Data {
        Data("{\"subaccount\": \(subaccountJSON(id: id)), \"action\": \(actionJSON(command: "create_subaccount"))}".utf8)
    }

    static func subaccountsPageJSON(ids: [Int]) -> Data {
        let items = ids.map { subaccountJSON(id: $0) }.joined(separator: ",")
        return Data("{\"subaccounts\": [\(items)]}".utf8)
    }
}

@Suite("StorageBoxClient")
struct StorageBoxAPITests {
    private func makeClient(responses: [MockTransport.ScriptedResponse]) -> (StorageBoxClient, MockTransport) {
        let transport = MockTransport(responses: responses)
        let client = StorageBoxClient(token: "test-token", transport: transport)
        return (client, transport)
    }

    private func decodedBody(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    // MARK: - List / get / pagination

    @Test func listStorageBoxesWalksAllPages() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: StorageBoxFixtures.storageBoxesPageJSON(boxes: [(1, "a"), (2, "b")], nextPage: 2)),
            .init(statusCode: 200, data: StorageBoxFixtures.storageBoxesPageJSON(boxes: [(3, "c")], nextPage: nil)),
        ])

        let boxes = try await client.listStorageBoxes()

        #expect(boxes.map(\.id) == [1, 2, 3])

        let requests = await transport.recordedRequests
        #expect(requests.count == 2)
        #expect(requests[0].url?.absoluteString.hasPrefix("https://api.hetzner.com/v1/storage_boxes") == true)
        #expect(requests[0].httpMethod == "GET")
    }

    @Test func storageBoxFetchesSingleByIDAndDecodesNestedFields() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: StorageBoxFixtures.storageBoxEnvelopeJSON(id: 55, name: "solo")),
        ])

        let box = try await client.storageBox(id: 55)

        #expect(box.id == 55)
        #expect(box.name == "solo")
        #expect(box.status == .active)
        #expect(box.location.name == "fsn1")
        #expect(box.storageBoxType.name == "bx11")
        #expect(box.storageBoxType.prices.first?.setupFee.net == "0.00")
        #expect(box.accessSettings.sshEnabled == true)
        #expect(box.accessSettings.sambaEnabled == false)
        #expect(box.server == "u55.your-storagebox.de")
        #expect(box.stats.sizeData == 800)
        #expect(box.labels["env"] == "prod")
        #expect(box.snapshotPlan == nil)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.com/v1/storage_boxes/55")
    }

    @Test func unknownStatusDecodesToUnknownInsteadOfThrowing() async throws {
        let (client, _) = makeClient(responses: [
            .init(statusCode: 200, data: StorageBoxFixtures.storageBoxEnvelopeJSON(id: 1)
                .withStatusReplaced(to: "some_future_status")),
        ])

        let box = try await client.storageBox(id: 1)
        #expect(box.status == .unknown)
    }

    // MARK: - Update

    @Test func updateStorageBoxSendsPUTWithOnlyProvidedFields() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: StorageBoxFixtures.storageBoxEnvelopeJSON(id: 100, name: "renamed")),
        ])

        let box = try await client.updateStorageBox(id: 100, name: "renamed", labels: ["a": "b"])
        #expect(box.name == "renamed")

        let requests = await transport.recordedRequests
        #expect(requests[0].httpMethod == "PUT")
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.com/v1/storage_boxes/100")

        let body = try decodedBody(requests[0])
        #expect(body["name"] as? String == "renamed")
        #expect((body["labels"] as? [String: String])?["a"] == "b")
    }

    @Test func updateStorageBoxLabelsOnlyOmitsNameFromBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: StorageBoxFixtures.storageBoxEnvelopeJSON()),
        ])

        _ = try await client.updateStorageBox(id: 100, labels: ["env": "staging"])

        let requests = await transport.recordedRequests
        let body = try decodedBody(requests[0])
        #expect(body["name"] == nil)
        #expect((body["labels"] as? [String: String])?["env"] == "staging")
    }

    // MARK: - Delete

    @Test func deleteStorageBoxSendsDELETEAndDecodesAction() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: StorageBoxFixtures.actionEnvelopeJSON(command: "delete_storage_box")),
        ])

        let action = try await client.deleteStorageBox(id: 100)
        #expect(action.command == "delete_storage_box")

        let requests = await transport.recordedRequests
        #expect(requests[0].httpMethod == "DELETE")
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.com/v1/storage_boxes/100")
    }

    // MARK: - Protocol / access settings action

    @Test func updateAccessSettingsSendsOnlyProvidedProtocolTogglesToActionPath() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: StorageBoxFixtures.actionEnvelopeJSON(command: "update_access_settings")),
        ])

        let action = try await client.updateAccessSettings(id: 100, sambaEnabled: true, webdavEnabled: true)
        #expect(action.command == "update_access_settings")

        let requests = await transport.recordedRequests
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.com/v1/storage_boxes/100/actions/update_access_settings")

        let body = try decodedBody(requests[0])
        #expect(body["samba_enabled"] as? Bool == true)
        #expect(body["webdav_enabled"] as? Bool == true)
        #expect(body["ssh_enabled"] == nil)
        #expect(body["reachable_externally"] == nil)
        #expect(body["zfs_enabled"] == nil)
    }

    // MARK: - Reset password (secret never in URL)

    @Test func resetPasswordSendsPasswordOnlyInBodyNeverInURL() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: StorageBoxFixtures.actionEnvelopeJSON(command: "reset_password")),
        ])

        let action = try await client.resetPassword(id: 100, newPassword: "S3cret!Passw0rd")
        #expect(action.command == "reset_password")

        let requests = await transport.recordedRequests
        let urlString = requests[0].url?.absoluteString ?? ""
        #expect(urlString == "https://api.hetzner.com/v1/storage_boxes/100/actions/reset_password")
        #expect(urlString.contains("S3cret") == false)

        let body = try decodedBody(requests[0])
        #expect(body["password"] as? String == "S3cret!Passw0rd")
    }

    @Test func resetSubaccountPasswordSendsPasswordOnlyInBodyNeverInURL() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: StorageBoxFixtures.actionEnvelopeJSON(command: "reset_subaccount_password")),
        ])

        _ = try await client.resetSubaccountPassword(storageBoxID: 100, id: 1, newPassword: "An0ther$ecret")

        let requests = await transport.recordedRequests
        let urlString = requests[0].url?.absoluteString ?? ""
        #expect(urlString == "https://api.hetzner.com/v1/storage_boxes/100/subaccounts/1/actions/reset_subaccount_password")
        #expect(urlString.contains("An0ther") == false)

        let body = try decodedBody(requests[0])
        #expect(body["password"] as? String == "An0ther$ecret")
    }

    // MARK: - Snapshots

    @Test func listSnapshotsDecodesSnapshotFields() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: StorageBoxFixtures.snapshotsPageJSON(ids: [1, 2])),
        ])

        let snapshots = try await client.listSnapshots(storageBoxID: 100)
        #expect(snapshots.map(\.id) == [1, 2])
        #expect(snapshots[0].storageBoxID == 100)
        #expect(snapshots[0].isAutomatic == false)
        #expect(snapshots[0].stats.sizeFilesystem == 600)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString.contains("/storage_boxes/100/snapshots") == true)
    }

    @Test func createSnapshotSendsExpectedBodyAndDecodesActionAndSnapshot() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: StorageBoxFixtures.snapshotCreateResponseJSON(id: 7)),
        ])

        let result = try await client.createSnapshot(storageBoxID: 100, description: "pre-migration", labels: ["kind": "manual"])
        #expect(result.snapshot.id == 7)
        #expect(result.action.command == "create_snapshot")

        let requests = await transport.recordedRequests
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.com/v1/storage_boxes/100/snapshots")

        let body = try decodedBody(requests[0])
        #expect(body["description"] as? String == "pre-migration")
        #expect((body["labels"] as? [String: String])?["kind"] == "manual")
    }

    @Test func deleteSnapshotSendsDELETEAndDecodesAction() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: StorageBoxFixtures.actionEnvelopeJSON(command: "delete_snapshot")),
        ])

        let action = try await client.deleteSnapshot(storageBoxID: 100, id: 7)
        #expect(action.command == "delete_snapshot")

        let requests = await transport.recordedRequests
        #expect(requests[0].httpMethod == "DELETE")
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.com/v1/storage_boxes/100/snapshots/7")
    }

    @Test func rollbackSnapshotSendsSnapshotReferenceInBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: StorageBoxFixtures.actionEnvelopeJSON(command: "rollback_snapshot")),
        ])

        _ = try await client.rollbackSnapshot(id: 100, snapshot: "snap-1")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.com/v1/storage_boxes/100/actions/rollback_snapshot")
        let body = try decodedBody(requests[0])
        #expect(body["snapshot"] as? String == "snap-1")
    }

    // MARK: - Subaccounts

    @Test func createSubaccountSendsExpectedBodyAndDecodesActionAndSubaccount() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: StorageBoxFixtures.subaccountCreateResponseJSON(id: 3)),
        ])

        let result = try await client.createSubaccount(
            storageBoxID: 100,
            homeDirectory: "/backups",
            password: "Sub$Account123",
            description: "ci uploader",
            accessSettings: StorageBoxSubaccountAccessSettings(
                reachableExternally: true,
                readonly: false,
                sambaEnabled: false,
                sshEnabled: true,
                webdavEnabled: false
            ),
            labels: ["role": "ci"]
        )

        #expect(result.subaccount.id == 3)
        #expect(result.subaccount.homeDirectory == "/backups")
        #expect(result.subaccount.storageBoxID == 100)
        #expect(result.action.command == "create_subaccount")

        let requests = await transport.recordedRequests
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.com/v1/storage_boxes/100/subaccounts")

        let body = try decodedBody(requests[0])
        #expect(body["home_directory"] as? String == "/backups")
        #expect(body["password"] as? String == "Sub$Account123")
        #expect((body["access_settings"] as? [String: Any])?["ssh_enabled"] as? Bool == true)
        #expect((body["labels"] as? [String: String])?["role"] == "ci")
    }

    @Test func listSubaccountsWithUsernameFilterSetsQueryParameter() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: StorageBoxFixtures.subaccountsPageJSON(ids: [1])),
        ])

        let subaccounts = try await client.listSubaccounts(storageBoxID: 100, username: "sub1")
        #expect(subaccounts.map(\.id) == [1])

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.query?.contains("username=sub1") == true)
    }

    @Test func deleteSubaccountSendsDELETEAndDecodesAction() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: StorageBoxFixtures.actionEnvelopeJSON(command: "delete_subaccount")),
        ])

        let action = try await client.deleteSubaccount(storageBoxID: 100, id: 3)
        #expect(action.command == "delete_subaccount")

        let requests = await transport.recordedRequests
        #expect(requests[0].httpMethod == "DELETE")
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.com/v1/storage_boxes/100/subaccounts/3")
    }

    @Test func changeSubaccountHomeDirectorySendsExpectedBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: StorageBoxFixtures.actionEnvelopeJSON(command: "change_home_directory")),
        ])

        _ = try await client.changeSubaccountHomeDirectory(storageBoxID: 100, id: 3, homeDirectory: "/archive")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.com/v1/storage_boxes/100/subaccounts/3/actions/change_home_directory")
        let body = try decodedBody(requests[0])
        #expect(body["home_directory"] as? String == "/archive")
    }

    // MARK: - Snapshot plan

    @Test func enableSnapshotPlanSendsScheduleFields() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: StorageBoxFixtures.actionEnvelopeJSON(command: "enable_snapshot_plan")),
        ])

        _ = try await client.enableSnapshotPlan(id: 100, maxSnapshots: 5, minute: 30, hour: 3, dayOfWeek: 1)

        let requests = await transport.recordedRequests
        let body = try decodedBody(requests[0])
        #expect(body["max_snapshots"] as? Int == 5)
        #expect(body["minute"] as? Int == 30)
        #expect(body["hour"] as? Int == 3)
        #expect(body["day_of_week"] as? Int == 1)
        #expect(body["day_of_month"] == nil)
    }

    @Test func disableSnapshotPlanSendsNoBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: StorageBoxFixtures.actionEnvelopeJSON(command: "disable_snapshot_plan")),
        ])

        let action = try await client.disableSnapshotPlan(id: 100)
        #expect(action.command == "disable_snapshot_plan")

        let requests = await transport.recordedRequests
        #expect(requests[0].httpBody == nil)
    }

    // MARK: - Folders / types

    @Test func foldersSendsPathQueryAndDecodesList() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: Data(#"{"folders": ["/backups/2025", "/backups/2026"]}"#.utf8)),
        ])

        let folders = try await client.folders(id: 100, path: "/backups")
        #expect(folders == ["/backups/2025", "/backups/2026"])

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.query?.contains("path=%2Fbackups") == true || requests[0].url?.query?.contains("path=/backups") == true)
    }

    @Test func listStorageBoxTypesDecodesPricingIncludingSetupFee() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: Data("{\"storage_box_types\": [\(StorageBoxFixtures.storageBoxTypeJSON)]}".utf8)),
        ])

        let types = try await client.listStorageBoxTypes()
        #expect(types.count == 1)
        #expect(types[0].name == "bx11")
        #expect(types[0].prices[0].setupFee.gross == "0.00")
        #expect(types[0].subaccountsLimit == 200)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString.hasPrefix("https://api.hetzner.com/v1/storage_box_types") == true)
    }

    // MARK: - Error mapping / token validation

    @Test func validateTokenThrowsUnauthorizedOn401() async throws {
        let (client, _) = makeClient(responses: [
            .init(statusCode: 401, data: Data()),
        ])

        do {
            try await client.validateToken()
            Issue.record("Expected validateToken() to throw")
        } catch HetznerAPIError.unauthorized {
            // expected
        }
    }

    @Test func apiErrorEnvelopeMapsToHetznerAPIError() async throws {
        let (client, _) = makeClient(responses: [
            .init(statusCode: 400, data: Data(#"{"error":{"code":"invalid_input","message":"password too weak"}}"#.utf8)),
        ])

        do {
            _ = try await client.resetPassword(id: 100, newPassword: "short")
            Issue.record("Expected an error to be thrown")
        } catch HetznerAPIError.api(let code, let message) {
            #expect(code == "invalid_input")
            #expect(message == "password too weak")
        }
    }
}

// MARK: - Test helpers

private extension Data {
    /// Swaps the `"status": "..."` value in a single storage-box-envelope
    /// fixture, for exercising the unknown-status decoding path without a
    /// bespoke fixture builder.
    func withStatusReplaced(to newStatus: String) -> Data {
        let string = String(decoding: self, as: UTF8.self)
        let replaced = string.replacingOccurrences(of: "\"status\": \"active\"", with: "\"status\": \"\(newStatus)\"")
        return Data(replaced.utf8)
    }
}
