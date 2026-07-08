import Foundation
import Testing
@testable import HetznerKit

@Suite("CloudAPI model decoding")
struct CloudAPIModelDecodingTests {
    private let decoder = makeHetznerJSONDecoder()

    @Test func decodesFullServer() throws {
        let data = CloudAPIFixtures.serverEnvelopeJSON()
        let envelope = try decoder.decode(ServerEnvelope.self, from: data)
        let server = envelope.server

        #expect(server.id == 42)
        #expect(server.name == "web-01")
        #expect(server.status == .running)
        #expect(server.publicNet.ipv4?.ip == "1.2.3.4")
        #expect(server.publicNet.ipv6?.ip == "2001:db8::/64")
        #expect(server.serverType.id == 22)
        #expect(server.serverType.cpuType == .shared)
        #expect(server.serverType.architecture == .x86)
        #expect(server.serverType.prices.first?.hourly.netDecimal == Decimal(string: "0.0060"))
        #expect(server.datacenter.location.networkZone == "eu-central")
        #expect(server.labels == ["env": "prod"])
        #expect(server.locked == false)
        #expect(server.protection.delete == false)
        #expect(server.backupWindow == nil)
        #expect(server.rescueEnabled == false)
        #expect(server.primaryDiskSize == 40)
        #expect(server.includedTraffic == 21_990_232_555_520)
        #expect(server.outgoingTraffic == 123_456)
        #expect(server.ingoingTraffic == nil)
    }

    @Test func unknownServerStatusDecodesToUnknownInsteadOfThrowing() throws {
        let data = CloudAPIFixtures.serverEnvelopeJSON(status: "quantum-leaping")
        let envelope = try decoder.decode(ServerEnvelope.self, from: data)
        #expect(envelope.server.status == .unknown)
    }

    @Test func unknownCPUTypeAndArchitectureDecodeToUnknown() throws {
        let json = """
        {"id": 1, "name": "weird", "description": "", "cores": 1, "memory": 1.0, "disk": 10,
         "cpu_type": "quantum", "architecture": "risc-v", "deprecated": null, "prices": []}
        """
        let serverType = try decoder.decode(ServerType.self, from: Data(json.utf8))
        #expect(serverType.cpuType == .unknown)
        #expect(serverType.architecture == .unknown)
    }

    @Test func decodesActionEnvelope() throws {
        let data = CloudAPIFixtures.actionEnvelopeJSON(id: 7, command: "poweron", status: "running", progress: 20)
        let envelope = try decoder.decode(ActionEnvelope.self, from: data)

        #expect(envelope.action.id == 7)
        #expect(envelope.action.command == "poweron")
        #expect(envelope.action.status == .running)
        #expect(envelope.action.progress == 20)
        #expect(envelope.action.finished == nil)
        #expect(envelope.action.error == nil)
        #expect(envelope.action.resources.first?.type == "server")
    }

    @Test func decodesActionWithError() throws {
        let data = CloudAPIFixtures.actionEnvelopeJSON(
            status: "error",
            errorCode: "action_failed",
            errorMessage: "Server could not be started."
        )
        let envelope = try decoder.decode(ActionEnvelope.self, from: data)

        #expect(envelope.action.status == .error)
        #expect(envelope.action.error?.code == "action_failed")
        #expect(envelope.action.error?.message == "Server could not be started.")
    }

    @Test func unknownActionStatusDecodesToUnknown() throws {
        let data = CloudAPIFixtures.actionEnvelopeJSON(status: "teleporting")
        let envelope = try decoder.decode(ActionEnvelope.self, from: data)
        #expect(envelope.action.status == .unknown)
    }

    @Test func decodesPricing() throws {
        let pricing = try decoder.decode(Pricing.self, from: CloudAPIFixtures.pricingJSON)

        #expect(pricing.currency == "EUR")
        #expect(pricing.vatRate == "19.00")
        #expect(pricing.serverTypes.count == 1)
        #expect(pricing.serverTypes.first?.name == "cx22")
        #expect(pricing.primaryIPs.first?.type == "ipv4")
        #expect(pricing.volumePerGBMonth?.net == "0.0400")
        #expect(pricing.serverBackupPercentage == "20.00")
    }

    @Test func pricingToleratesMissingOptionalSections() throws {
        let json = Data(
            """
            {"pricing": {"currency": "EUR", "vat_rate": "19.00"}}
            """.utf8
        )
        let pricing = try decoder.decode(Pricing.self, from: json)

        #expect(pricing.currency == "EUR")
        #expect(pricing.serverTypes.isEmpty)
        #expect(pricing.primaryIPs.isEmpty)
        #expect(pricing.volumePerGBMonth == nil)
        #expect(pricing.serverBackupPercentage == nil)
    }
}
