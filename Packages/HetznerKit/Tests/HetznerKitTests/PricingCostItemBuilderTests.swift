import Foundation
import Testing
@testable import HetznerKit

@Suite("CostItemBuilder")
struct PricingCostItemBuilderTests {
    private static func location(_ name: String) -> Location {
        Location(id: 1, name: name, description: name, country: "DE", city: "Falkenstein", latitude: 0, longitude: 0, networkZone: "eu-central")
    }

    private static func datacenter(location name: String) -> Datacenter {
        Datacenter(id: 1, name: "\(name)-dc1", description: "", location: location(name))
    }

    private static func serverType(prices: [ServerTypePrice]) -> ServerType {
        ServerType(
            id: 22, name: "cx22", description: "", cores: 2, memory: 4, disk: 40,
            cpuType: .shared, architecture: .x86, deprecated: false, prices: prices
        )
    }

    private static func server(
        id: Int = 1,
        name: String = "web-1",
        created: Date,
        location: String = "fsn1",
        prices: [ServerTypePrice],
        backupWindow: String? = nil
    ) -> Server {
        Server(
            id: id, name: name, status: .running, created: created,
            publicNet: PublicNet(ipv4: nil, ipv6: nil),
            serverType: serverType(prices: prices),
            datacenter: datacenter(location: location),
            labels: [:], locked: false,
            protection: ServerProtection(delete: false, rebuild: false),
            backupWindow: backupWindow, rescueEnabled: false, primaryDiskSize: 40,
            includedTraffic: nil, outgoingTraffic: nil, ingoingTraffic: nil
        )
    }

    private static func pricing(serverTypes: [PricingServerType], backupPercentage: String?) -> Pricing {
        Pricing(
            currency: "EUR", vatRate: "19.00", serverTypes: serverTypes, primaryIPs: [],
            volumePerGBMonth: nil, serverBackupPercentage: backupPercentage
        )
    }

    @Test func mapsServerToHourlyCostItemUsingItsLocationPrice() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let fsn1 = ServerTypePrice(location: "fsn1", hourly: PriceValue(net: "0.0060", gross: "0.00714"), monthly: PriceValue(net: "4.00", gross: "4.76"))
        let hel1 = ServerTypePrice(location: "hel1", hourly: PriceValue(net: "0.0070", gross: "0.00833"), monthly: PriceValue(net: "5.00", gross: "5.95"))
        let s = Self.server(created: created, location: "fsn1", prices: [hel1, fsn1])
        let p = Self.pricing(serverTypes: [PricingServerType(id: 22, name: "cx22", prices: [hel1, fsn1])], backupPercentage: nil)

        let items = CostItemBuilder.items(servers: [s], pricing: p)

        #expect(items.count == 1)
        #expect(items[0].id == "server-1")
        #expect(items[0].kind == .server)
        #expect(items[0].createdAt == created)
        guard case .hourly(let net, let cap) = items[0].pricing else {
            Issue.record("expected hourly pricing")
            return
        }
        #expect(net == Decimal(string: "0.0060")!)
        #expect(cap == Decimal(string: "4.00")!)
    }

    @Test func fallsBackToFirstPriceWhenLocationHasNoExactMatch() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let hel1 = ServerTypePrice(location: "hel1", hourly: PriceValue(net: "0.0070", gross: "0.00833"), monthly: PriceValue(net: "5.00", gross: "5.95"))
        // Server reports a location ("nbg1") absent from the price list.
        let s = Self.server(created: created, location: "nbg1", prices: [hel1])
        let p = Self.pricing(serverTypes: [PricingServerType(id: 22, name: "cx22", prices: [hel1])], backupPercentage: nil)

        let items = CostItemBuilder.items(servers: [s], pricing: p)

        #expect(items.count == 1)
        guard case .hourly(let net, _) = items[0].pricing else {
            Issue.record("expected hourly pricing")
            return
        }
        #expect(net == Decimal(string: "0.0070")!)
    }

    @Test func fallsBackToServerTypeEmbeddedPricesWhenMissingFromPricingList() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let fsn1 = ServerTypePrice(location: "fsn1", hourly: PriceValue(net: "0.0060", gross: "0.00714"), monthly: PriceValue(net: "4.00", gross: "4.76"))
        let s = Self.server(created: created, location: "fsn1", prices: [fsn1])
        // Pricing list has no entry at all for this server type id.
        let p = Self.pricing(serverTypes: [], backupPercentage: nil)

        let items = CostItemBuilder.items(servers: [s], pricing: p)

        #expect(items.count == 1)
        guard case .hourly(let net, _) = items[0].pricing else {
            Issue.record("expected hourly pricing")
            return
        }
        #expect(net == Decimal(string: "0.0060")!)
    }

    @Test func addsBackupSurchargeItemWhenBackupWindowPresent() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let fsn1 = ServerTypePrice(location: "fsn1", hourly: PriceValue(net: "0.0060", gross: "0.00714"), monthly: PriceValue(net: "4.00", gross: "4.76"))
        let s = Self.server(created: created, location: "fsn1", prices: [fsn1], backupWindow: "22-02")
        let p = Self.pricing(serverTypes: [PricingServerType(id: 22, name: "cx22", prices: [fsn1])], backupPercentage: "20")

        let items = CostItemBuilder.items(servers: [s], pricing: p)

        #expect(items.count == 2)
        let backup = items.first { $0.kind == .backup }
        #expect(backup != nil)
        guard case .monthlyFlat(let net) = backup?.pricing else {
            Issue.record("expected monthlyFlat pricing")
            return
        }
        // 20% of 4.00 = 0.80
        #expect(net == Decimal(string: "0.80")!)
    }

    @Test func omitsBackupItemWhenNoBackupWindow() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let fsn1 = ServerTypePrice(location: "fsn1", hourly: PriceValue(net: "0.0060", gross: "0.00714"), monthly: PriceValue(net: "4.00", gross: "4.76"))
        let s = Self.server(created: created, location: "fsn1", prices: [fsn1], backupWindow: nil)
        let p = Self.pricing(serverTypes: [PricingServerType(id: 22, name: "cx22", prices: [fsn1])], backupPercentage: "20")

        let items = CostItemBuilder.items(servers: [s], pricing: p)

        #expect(items.count == 1)
        #expect(items[0].kind == .server)
    }

    @Test func skipsServerWhenNoPriceCanBeResolved() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let s = Self.server(created: created, location: "fsn1", prices: [])
        let p = Self.pricing(serverTypes: [], backupPercentage: nil)

        let items = CostItemBuilder.items(servers: [s], pricing: p)

        #expect(items.isEmpty)
    }

    // MARK: - Overrides ("what I actually pay")

    @Test func overrideWinsOverListPriceAndBecomesMonthlyFlat() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let fsn1 = ServerTypePrice(location: "fsn1", hourly: PriceValue(net: "0.0060", gross: "0.00714"), monthly: PriceValue(net: "4.00", gross: "4.76"))
        let s = Self.server(id: 42, created: created, location: "fsn1", prices: [fsn1])
        let p = Self.pricing(serverTypes: [PricingServerType(id: 22, name: "cx22", prices: [fsn1])], backupPercentage: nil)

        let items = CostItemBuilder.items(servers: [s], pricing: p, overrides: [42: Decimal(string: "25.49")!])

        #expect(items.count == 1)
        #expect(items[0].id == "server-42")
        #expect(items[0].kind == .server)
        #expect(items[0].createdAt == created)
        guard case .monthlyFlat(let net) = items[0].pricing else {
            Issue.record("expected monthlyFlat pricing")
            return
        }
        #expect(net == Decimal(string: "25.49")!)
    }

    @Test func overrideSkipsBackupSurchargeEvenWithBackupWindow() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let fsn1 = ServerTypePrice(location: "fsn1", hourly: PriceValue(net: "0.0060", gross: "0.00714"), monthly: PriceValue(net: "4.00", gross: "4.76"))
        let s = Self.server(id: 42, created: created, location: "fsn1", prices: [fsn1], backupWindow: "22-02")
        let p = Self.pricing(serverTypes: [PricingServerType(id: 22, name: "cx22", prices: [fsn1])], backupPercentage: "20")

        let items = CostItemBuilder.items(servers: [s], pricing: p, overrides: [42: Decimal(string: "25.49")!])

        // A user-entered "what I pay" figure is assumed all-in — no separate
        // backup line for this server.
        #expect(items.count == 1)
        #expect(items[0].kind == .server)
    }

    @Test func overrideAppliesEvenWhenNoPriceCanBeResolved() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        // No prices anywhere for this server's type — without an override
        // this server would be skipped entirely (see
        // `skipsServerWhenNoPriceCanBeResolved`).
        let s = Self.server(id: 7, created: created, location: "fsn1", prices: [])
        let p = Self.pricing(serverTypes: [], backupPercentage: nil)

        let items = CostItemBuilder.items(servers: [s], pricing: p, overrides: [7: Decimal(string: "10.00")!])

        #expect(items.count == 1)
        guard case .monthlyFlat(let net) = items[0].pricing else {
            Issue.record("expected monthlyFlat pricing")
            return
        }
        #expect(net == Decimal(string: "10.00")!)
    }

    @Test func emptyOverridesLeaveExistingBehaviorUnchanged() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let fsn1 = ServerTypePrice(location: "fsn1", hourly: PriceValue(net: "0.0060", gross: "0.00714"), monthly: PriceValue(net: "4.00", gross: "4.76"))
        let s = Self.server(id: 1, created: created, location: "fsn1", prices: [fsn1])
        let p = Self.pricing(serverTypes: [PricingServerType(id: 22, name: "cx22", prices: [fsn1])], backupPercentage: nil)

        let withDefault = CostItemBuilder.items(servers: [s], pricing: p)
        let withExplicitEmpty = CostItemBuilder.items(servers: [s], pricing: p, overrides: [:])

        #expect(withDefault == withExplicitEmpty)
        guard case .hourly(let net, _) = withDefault[0].pricing else {
            Issue.record("expected hourly pricing")
            return
        }
        #expect(net == Decimal(string: "0.0060")!)
    }

    @Test func multiServerMixOnlyOverriddenServerBecomesFlatAndOthersUnaffected() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let fsn1 = ServerTypePrice(location: "fsn1", hourly: PriceValue(net: "0.0060", gross: "0.00714"), monthly: PriceValue(net: "4.00", gross: "4.76"))
        let overridden = Self.server(id: 1, name: "grandfathered-1", created: created, location: "fsn1", prices: [fsn1], backupWindow: "22-02")
        let plain = Self.server(id: 2, name: "plain-1", created: created, location: "fsn1", prices: [fsn1], backupWindow: "22-02")
        let p = Self.pricing(serverTypes: [PricingServerType(id: 22, name: "cx22", prices: [fsn1])], backupPercentage: "20")

        let items = CostItemBuilder.items(servers: [overridden, plain], pricing: p, overrides: [1: Decimal(string: "9.99")!])

        // Overridden server: just the flat item, no backup.
        let overriddenItems = items.filter { $0.id == "server-1" || $0.id == "backup-1" }
        #expect(overriddenItems.count == 1)
        guard case .monthlyFlat(let net) = overriddenItems[0].pricing else {
            Issue.record("expected monthlyFlat pricing for overridden server")
            return
        }
        #expect(net == Decimal(string: "9.99")!)

        // Untouched server: hourly item + its backup surcharge, unaffected.
        let plainItems = items.filter { $0.id == "server-2" || $0.id == "backup-2" }
        #expect(plainItems.count == 2)
        #expect(plainItems.contains { $0.kind == .backup })

        #expect(items.count == 3)
    }

    @Test func buildsFeedIntoCostEngineEndToEnd() {
        // Sanity check: builder output is a valid CostEngine input and
        // produces a non-trivial summary.
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let fsn1 = ServerTypePrice(location: "fsn1", hourly: PriceValue(net: "0.0060", gross: "0.00714"), monthly: PriceValue(net: "4.00", gross: "4.76"))
        let s = Self.server(created: created, location: "fsn1", prices: [fsn1], backupWindow: "22-02")
        let p = Self.pricing(serverTypes: [PricingServerType(id: 22, name: "cx22", prices: [fsn1])], backupPercentage: "20")

        let items = CostItemBuilder.items(servers: [s], pricing: p)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let now = Date(timeIntervalSince1970: 1_700_100_000)

        let summary = CostEngine.summary(items: items, now: now, calendar: calendar, currency: p.currency)

        #expect(summary.perItem.count == 2)
        #expect(summary.currency == "EUR")
        #expect(summary.projectedMonthTotal > 0)
    }
}
