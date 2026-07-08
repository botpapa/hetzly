import Foundation
import Testing
@testable import HetznerKit

@Suite("Robot API models")
struct RobotAPIModelTests {
    private let decoder = JSONDecoder()

    // MARK: - RobotServer

    @Test func robotServerDecodesFullShapeIncludingIPAndSubnetArrays() throws {
        let data = Data(RobotFixtures.serverObjectJSON(number: 7, name: "web-01", status: "ready").utf8)
        let server = try decoder.decode(RobotServer.self, from: data)

        #expect(server.serverNumber == 7)
        #expect(server.id == 7)
        #expect(server.serverName == "web-01")
        #expect(server.product == "AX41-NVMe")
        #expect(server.dc == "FSN1-DC8")
        #expect(server.traffic == "20 TB")
        #expect(server.status == .ready)
        #expect(server.cancelled == false)
        #expect(server.paidUntil == "2026-12-31")
        #expect(server.ip == ["123.45.67.7"])
        #expect(server.subnet?.first?.ip == "2a01:4f8::7")
        #expect(server.subnet?.first?.mask == "64")
    }

    @Test func robotServerStatusDecodesInProcessFromWireValueWithSpace() throws {
        let data = Data(RobotFixtures.serverObjectJSON(status: "in process").utf8)
        let server = try decoder.decode(RobotServer.self, from: data)
        #expect(server.status == .inProcess)
    }

    @Test func robotServerStatusFallsBackToUnknownForUnrecognizedValue() throws {
        let data = Data(RobotFixtures.serverObjectJSON(status: "something-new").utf8)
        let server = try decoder.decode(RobotServer.self, from: data)
        #expect(server.status == .unknown)
    }

    @Test func wrappedListDecodingViaRobotDecodingHelper() throws {
        let data = RobotFixtures.serverListWrappedJSON([(1, "alpha"), (2, "beta"), (3, "gamma")])
        let servers: [RobotServer] = try RobotDecoding.decodeWrappedList(key: "server", from: data, using: decoder)
        #expect(servers.map(\.serverName) == ["alpha", "beta", "gamma"])
    }

    @Test func wrappedSingleDecodingViaRobotDecodingHelper() throws {
        let data = RobotFixtures.serverWrappedJSON(number: 99, name: "solo")
        let server: RobotServer = try RobotDecoding.decodeWrapped(key: "server", from: data, using: decoder)
        #expect(server.serverNumber == 99)
    }

    // MARK: - RobotResetType / RobotResetInfo

    @Test func resetTypeExposesTitleAndPlainExplanationForAllCases() {
        for type in RobotResetType.allCases {
            #expect(!type.title.isEmpty)
            #expect(!type.plainExplanation.isEmpty)
        }
        #expect(RobotResetType.sw.plainExplanation.contains("CTRL+ALT+DEL"))
        #expect(RobotResetType.hw.plainExplanation.contains("reset button"))
        #expect(RobotResetType.man.plainExplanation.contains("technician"))
    }

    @Test func resetInfoDecodesAvailableTypesAndDropsUnknownValues() throws {
        let data = RobotFixtures.resetInfoWrappedJSON(number: 3, types: ["sw", "hw", "man", "future-type"], operatingStatus: "not-supported")
        let info: RobotResetInfo = try RobotDecoding.decodeWrapped(key: "reset", from: data, using: decoder)

        #expect(info.serverNumber == 3)
        #expect(info.type == ["sw", "hw", "man", "future-type"])
        #expect(info.availableTypes == [.sw, .hw, .man])
        #expect(info.operatingStatus == "not-supported")
    }

    @Test func resetInfoDecodesNullOperatingStatus() throws {
        let data = RobotFixtures.resetInfoWrappedJSON(types: ["hw"], operatingStatus: nil)
        let info: RobotResetInfo = try RobotDecoding.decodeWrapped(key: "reset", from: data, using: decoder)
        #expect(info.operatingStatus == nil)
    }

    // MARK: - RobotRescue

    @Test func rescueDecodesActiveFlagAndTolerantAuthorizedKeyShape() throws {
        let json = """
        {"rescue": {"server_ip": "1.2.3.4", "server_number": 1, "os": "linux", "active": true,
        "password": "secret", "authorized_key": [{"fingerprint": "aa:bb"}, "cc:dd"]}}
        """
        let rescue: RobotRescue = try RobotDecoding.decodeWrapped(key: "rescue", from: Data(json.utf8), using: decoder)

        #expect(rescue.os == "linux")
        #expect(rescue.active == true)
        #expect(rescue.password == "secret")
        #expect(rescue.authorizedKey?.count == 2)
    }

    @Test func rescueDecodesNilPasswordWhenAbsent() throws {
        let data = RobotFixtures.rescueWrappedJSON(os: "linux", active: false, password: nil)
        let rescue: RobotRescue = try RobotDecoding.decodeWrapped(key: "rescue", from: data, using: decoder)
        #expect(rescue.password == nil)
        #expect(rescue.active == false)
    }

    // MARK: - RobotBootConfiguration

    @Test func bootConfigurationDecodesRescueLinuxAndVNCTogether() throws {
        let json = """
        {"boot": {
            "rescue": {"server_ip": "1.2.3.4", "os": "linux", "active": true, "password": "pw"},
            "linux": {"dist": ["Debian 12", "Ubuntu 24.04"], "active": false, "password": null},
            "vnc": {"dist": "Windows 2022", "active": true, "password": "vncpw"}
        }}
        """
        let config: RobotBootConfiguration = try RobotDecoding.decodeWrapped(key: "boot", from: Data(json.utf8), using: decoder)

        #expect(config.rescue?.os == "linux")
        #expect(config.linux?.dist == ["Debian 12", "Ubuntu 24.04"])
        #expect(config.linux?.active == false)
        #expect(config.vnc?.dist == ["Windows 2022"])
        #expect(config.vnc?.password == "vncpw")
    }

    @Test func bootConfigurationToleratesAllSectionsMissing() throws {
        let data = Data(#"{"boot": {}}"#.utf8)
        let config: RobotBootConfiguration = try RobotDecoding.decodeWrapped(key: "boot", from: data, using: decoder)
        #expect(config.rescue == nil)
        #expect(config.linux == nil)
        #expect(config.vnc == nil)
    }

    // MARK: - RobotRDNS

    @Test func rdnsDecodesIPAndPTR() throws {
        let data = RobotFixtures.rdnsWrappedJSON(ip: "5.6.7.8", ptr: "box.example.com")
        let rdns: RobotRDNS = try RobotDecoding.decodeWrapped(key: "rdns", from: data, using: decoder)
        #expect(rdns.ip == "5.6.7.8")
        #expect(rdns.ptr == "box.example.com")
        #expect(rdns.id == "5.6.7.8")
    }

    // MARK: - RobotIP / RobotSubnet

    @Test func robotIPDecodesOptionalFields() throws {
        let data = Data(#"[{"ip": {"ip": "9.9.9.9", "server_number": 42, "locked": true, "traffic_warnings": false}}]"#.utf8)
        let ips: [RobotIP] = try RobotDecoding.decodeWrappedList(key: "ip", from: data, using: decoder)
        #expect(ips.count == 1)
        #expect(ips[0].ip == "9.9.9.9")
        #expect(ips[0].serverNumber == 42)
        #expect(ips[0].locked == true)
        #expect(ips[0].trafficWarnings == false)
        #expect(ips[0].id == "9.9.9.9")
    }

    @Test func robotSubnetDecodesGatewayWhenPresent() throws {
        let data = Data(#"[{"subnet": {"ip": "10.0.0.0", "mask": "24", "server_number": 7, "gateway": "10.0.0.1"}}]"#.utf8)
        let subnets: [RobotSubnet] = try RobotDecoding.decodeWrappedList(key: "subnet", from: data, using: decoder)
        #expect(subnets.count == 1)
        #expect(subnets[0].gateway == "10.0.0.1")
        #expect(subnets[0].serverNumber == 7)
    }

    // MARK: - RobotSSHKey

    @Test func robotSSHKeyDecodesFingerprintAsIdentity() throws {
        let data = RobotFixtures.keyListWrappedJSON([("laptop", "aa:bb:cc:dd")])
        let keys: [RobotSSHKey] = try RobotDecoding.decodeWrappedList(key: "key", from: data, using: decoder)
        #expect(keys.count == 1)
        #expect(keys[0].name == "laptop")
        #expect(keys[0].fingerprint == "aa:bb:cc:dd")
        #expect(keys[0].id == "aa:bb:cc:dd")
    }
}
