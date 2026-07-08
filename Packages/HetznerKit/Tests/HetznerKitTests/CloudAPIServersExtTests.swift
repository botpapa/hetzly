import Foundation
import Testing
@testable import HetznerKit

@Suite("CloudClient+Servers (M2 Wave A)")
struct CloudAPIServersExtTests {
    private func makeClient(responses: [MockTransport.ScriptedResponse]) -> (CloudClient, MockTransport) {
        let transport = MockTransport(responses: responses)
        let client = CloudClient(token: "test-token", transport: transport)
        return (client, transport)
    }

    private func bodyJSON(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    // MARK: - createServer

    @Test func createServerSendsFullRequestBodyAndDecodesRootPassword() async throws {
        let responseJSON = """
        {
            "server": \(CloudAPIFixtures.serverJSON(id: 7, name: "new-box")),
            "action": \(CloudAPIFixtures.actionJSON(id: 1, command: "create_server")),
            "next_actions": [\(CloudAPIFixtures.actionJSON(id: 2, command: "start_server"))],
            "root_password": "s3cr3t-pw"
        }
        """
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: Data(responseJSON.utf8)),
        ])

        let request = CreateServerRequest(
            name: "new-box",
            serverType: "cx22",
            image: "ubuntu-24.04",
            location: "fsn1",
            sshKeys: ["my-key"],
            volumes: [101],
            networks: [55],
            firewalls: [.init(firewall: 9)],
            userData: "#cloud-config\nfoo: bar",
            labels: ["env": "prod"],
            automount: true,
            backups: true,
            publicNet: .init(enableIPv4: true, enableIPv6: false),
            startAfterCreate: true
        )

        let result = try await client.createServer(request)

        #expect(result.server.id == 7)
        #expect(result.action.command == "create_server")
        #expect(result.nextActions.map(\.id) == [2])
        #expect(result.rootPassword == "s3cr3t-pw")

        let requests = await transport.recordedRequests
        #expect(requests.count == 1)
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/servers")
        #expect(requests[0].httpMethod == "POST")

        let body = try bodyJSON(requests[0])
        #expect(body["name"] as? String == "new-box")
        #expect(body["server_type"] as? String == "cx22")
        #expect(body["image"] as? String == "ubuntu-24.04")
        #expect(body["location"] as? String == "fsn1")
        #expect(body["ssh_keys"] as? [String] == ["my-key"])
        #expect(body["volumes"] as? [Int] == [101])
        #expect(body["networks"] as? [Int] == [55])
        let firewalls = try #require(body["firewalls"] as? [[String: Int]])
        #expect(firewalls == [["firewall": 9]])
        #expect(body["user_data"] as? String == "#cloud-config\nfoo: bar")
        #expect(body["labels"] as? [String: String] == ["env": "prod"])
        #expect(body["automount"] as? Bool == true)
        #expect(body["backups"] as? Bool == true)
        let publicNet = try #require(body["public_net"] as? [String: Bool])
        #expect(publicNet == ["enable_ipv4": true, "enable_ipv6": false])
        #expect(body["start_after_create"] as? Bool == true)
        // Fields left nil at the call site must be omitted, not sent as null.
        #expect(body["datacenter"] == nil)
        #expect(body["placement_group"] == nil)
    }

    @Test func createServerOmitsOptionalFieldsWhenNilAndTolerhatesMissingRootPassword() async throws {
        let responseJSON = """
        {
            "server": \(CloudAPIFixtures.serverJSON(id: 8, name: "keyed-box")),
            "action": \(CloudAPIFixtures.actionJSON(id: 3, command: "create_server")),
            "next_actions": []
        }
        """
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: Data(responseJSON.utf8)),
        ])

        let result = try await client.createServer(
            CreateServerRequest(name: "keyed-box", serverType: "cx22", image: "ubuntu-24.04")
        )

        #expect(result.rootPassword == nil)
        #expect(result.nextActions.isEmpty)

        let requests = await transport.recordedRequests
        let body = try bodyJSON(requests[0])
        #expect(body["location"] == nil)
        #expect(body["datacenter"] == nil)
        #expect(body["user_data"] == nil)
        #expect(body["automount"] == nil)
        #expect(body["backups"] == nil)
        #expect(body["public_net"] == nil)
        #expect(body["placement_group"] == nil)
        #expect(body["start_after_create"] == nil)
        // Non-optional array/dict fields are always present, even if empty.
        #expect(body["ssh_keys"] as? [String] == [])
        #expect(body["volumes"] as? [Int] == [])
        #expect(body["networks"] as? [Int] == [])
        #expect(body["firewalls"] as? [[String: Int]] == [])
        #expect(body["labels"] as? [String: String] == [:])
    }

    // MARK: - rebuild / changeType

    @Test func rebuildPostsImageBodyToRebuildPath() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: CloudAPIFixtures.actionEnvelopeJSON(command: "rebuild")),
        ])

        let action = try await client.rebuild(serverID: 5, imageIDOrName: "ubuntu-24.04")
        #expect(action.command == "rebuild")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/servers/5/actions/rebuild")
        #expect(requests[0].httpMethod == "POST")
        let body = try bodyJSON(requests[0])
        #expect(body["image"] as? String == "ubuntu-24.04")
    }

    @Test func changeTypePostsServerTypeAndUpgradeDiskBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: CloudAPIFixtures.actionEnvelopeJSON(command: "change_server_type")),
        ])

        let action = try await client.changeType(serverID: 5, serverTypeID: 23, upgradeDisk: true)
        #expect(action.command == "change_server_type")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/servers/5/actions/change_type")
        let body = try bodyJSON(requests[0])
        #expect(body["server_type"] as? Int == 23)
        #expect(body["upgrade_disk"] as? Bool == true)
    }

    // MARK: - rescue / backups

    @Test func enableRescueDecodesRootPasswordAndPostsSSHKeys() async throws {
        let responseJSON = """
        {"root_password": "rescue-pw", "action": \(CloudAPIFixtures.actionJSON(command: "enable_rescue"))}
        """
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: Data(responseJSON.utf8)),
        ])

        let result = try await client.enableRescue(serverID: 5, sshKeyIDs: [11, 12])
        #expect(result.rootPassword == "rescue-pw")
        #expect(result.action.command == "enable_rescue")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/servers/5/actions/enable_rescue")
        let body = try bodyJSON(requests[0])
        #expect(body["ssh_keys"] as? [Int] == [11, 12])
        #expect(body["type"] as? String == "linux64")
    }

    @Test func disableRescueAndBackupToggleActionsHitExpectedPaths() async throws {
        let cases: [(name: String, path: String)] = [
            ("disable_rescue", "disable_rescue"),
            ("enable_backup", "enable_backup"),
            ("disable_backup", "disable_backup"),
        ]

        for testCase in cases {
            let (client, transport) = makeClient(responses: [
                .init(statusCode: 200, data: CloudAPIFixtures.actionEnvelopeJSON(command: testCase.name)),
            ])

            let action: Action
            switch testCase.name {
            case "disable_rescue": action = try await client.disableRescue(serverID: 5)
            case "enable_backup": action = try await client.enableBackups(serverID: 5)
            case "disable_backup": action = try await client.disableBackups(serverID: 5)
            default: fatalError("unreachable")
            }

            #expect(action.command == testCase.name)
            let requests = await transport.recordedRequests
            #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/servers/5/actions/\(testCase.path)")
            #expect(requests[0].httpMethod == "POST")
        }
    }

    // MARK: - createImage / changeProtection

    @Test func createImagePostsDescriptionAndTypeAndDecodesImageAndAction() async throws {
        let responseJSON = """
        {
            "image": {
                "id": 900, "type": "snapshot", "status": "creating", "name": null,
                "description": "nightly backup", "image_size": null, "disk_size": 40.0,
                "created": "2016-01-30T23:50:00+00:00", "created_from": {"id": 5, "name": "new-box"},
                "bound_to": null, "os_flavor": "ubuntu", "os_version": "24.04",
                "architecture": "x86", "protection": {"delete": false}, "deprecated": null, "labels": {}
            },
            "action": \(CloudAPIFixtures.actionJSON(command: "create_image"))
        }
        """
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 201, data: Data(responseJSON.utf8)),
        ])

        let result = try await client.createImage(serverID: 5, description: "nightly backup", type: .snapshot)
        #expect(result.image.id == 900)
        #expect(result.image.type == .snapshot)
        #expect(result.action.command == "create_image")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/servers/5/actions/create_image")
        let body = try bodyJSON(requests[0])
        #expect(body["description"] as? String == "nightly backup")
        #expect(body["type"] as? String == "snapshot")
    }

    @Test func changeProtectionOmitsUnspecifiedField() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: CloudAPIFixtures.actionEnvelopeJSON(command: "change_protection")),
        ])

        let action = try await client.changeProtection(serverID: 5, delete: true)
        #expect(action.command == "change_protection")

        let requests = await transport.recordedRequests
        let body = try bodyJSON(requests[0])
        #expect(body["delete"] as? Bool == true)
        #expect(body["rebuild"] == nil)
    }

    // MARK: - resetPassword / requestConsole

    @Test func resetPasswordDecodesRootPasswordAndAction() async throws {
        let responseJSON = """
        {"root_password": "new-pw", "action": \(CloudAPIFixtures.actionJSON(command: "reset_password"))}
        """
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: Data(responseJSON.utf8)),
        ])

        let result = try await client.resetPassword(serverID: 5)
        #expect(result.rootPassword == "new-pw")
        #expect(result.action.command == "reset_password")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/servers/5/actions/reset_password")
        #expect(requests[0].httpMethod == "POST")
    }

    @Test func requestConsoleDecodesWSSURLAndPassword() async throws {
        let responseJSON = """
        {
            "wss_url": "wss://console.hetzner.cloud/?server_id=5&token=abc",
            "password": "console-pw",
            "action": \(CloudAPIFixtures.actionJSON(command: "request_console"))
        }
        """
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: Data(responseJSON.utf8)),
        ])

        let result = try await client.requestConsole(serverID: 5)
        #expect(result.wssURL.absoluteString == "wss://console.hetzner.cloud/?server_id=5&token=abc")
        #expect(result.password == "console-pw")
        #expect(result.action.command == "request_console")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/servers/5/actions/request_console")
    }

    // MARK: - rename / updateLabels

    @Test func renameSendsPUTWithNameBodyAndDecodesServer() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: CloudAPIFixtures.serverEnvelopeJSON(id: 5, name: "renamed")),
        ])

        let server = try await client.rename(serverID: 5, name: "renamed")
        #expect(server.name == "renamed")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/servers/5")
        #expect(requests[0].httpMethod == "PUT")
        let body = try bodyJSON(requests[0])
        #expect(body["name"] as? String == "renamed")
        #expect(body.count == 1)
    }

    @Test func updateLabelsSendsPUTWithLabelsBodyAndDecodesServer() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: CloudAPIFixtures.serverEnvelopeJSON(id: 5, name: "web-01")),
        ])

        let server = try await client.updateLabels(serverID: 5, labels: ["team": "infra"])
        #expect(server.id == 5)

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/servers/5")
        #expect(requests[0].httpMethod == "PUT")
        let body = try bodyJSON(requests[0])
        #expect(body["labels"] as? [String: String] == ["team": "infra"])
    }

    // MARK: - ISO attach/detach

    @Test func attachISOPostsISOBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: CloudAPIFixtures.actionEnvelopeJSON(command: "attach_iso")),
        ])

        let action = try await client.attachISO(serverID: 5, iso: "debian-12-netinst-amd64")
        #expect(action.command == "attach_iso")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/servers/5/actions/attach_iso")
        let body = try bodyJSON(requests[0])
        #expect(body["iso"] as? String == "debian-12-netinst-amd64")
    }

    @Test func detachISOPostsWithNoBody() async throws {
        let (client, transport) = makeClient(responses: [
            .init(statusCode: 200, data: CloudAPIFixtures.actionEnvelopeJSON(command: "detach_iso")),
        ])

        let action = try await client.detachISO(serverID: 5)
        #expect(action.command == "detach_iso")

        let requests = await transport.recordedRequests
        #expect(requests[0].url?.absoluteString == "https://api.hetzner.cloud/v1/servers/5/actions/detach_iso")
        #expect(requests[0].httpBody == nil)
    }
}
