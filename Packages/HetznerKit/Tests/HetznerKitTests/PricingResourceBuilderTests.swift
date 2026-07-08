import Foundation
import Testing
@testable import HetznerKit

@Suite("CostItemBuilder+Resources")
struct PricingResourceBuilderTests {
    private static func location(_ name: String) -> Location {
        Location(id: 1, name: name, description: name, country: "DE", city: "Falkenstein", latitude: 0, longitude: 0, networkZone: "eu-central")
    }

    private static func datacenter(location name: String) -> Datacenter {
        Datacenter(id: 1, name: "\(name)-dc1", description: "", location: location(name))
    }

    private static func pricing(
        volumePerGBMonth: PriceValue? = nil,
        primaryIPs: [PricingPrimaryIP] = []
    ) -> Pricing {
        Pricing(
            currency: "EUR", vatRate: "19.00", serverTypes: [], primaryIPs: primaryIPs,
            volumePerGBMonth: volumePerGBMonth, serverBackupPercentage: nil
        )
    }

    // MARK: - Volumes

    private static func volume(
        id: Int = 1,
        name: String = "data-1",
        created: Date,
        size: Int,
        locationName: String = "fsn1"
    ) -> Volume {
        Volume(
            id: id, created: created, name: name, server: nil,
            location: location(locationName), size: size, linuxDevice: "/dev/disk/by-id/scsi-0HC_Volume_1",
            protection: VolumeProtection(delete: false), status: .available, format: nil, labels: [:]
        )
    }

    @Test func volumeCostIsPerGBPriceTimesSize() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let v = Self.volume(created: created, size: 10)
        let p = Self.pricing(volumePerGBMonth: PriceValue(net: "0.0400", gross: "0.0476"))

        let items = CostItemBuilder.items(volumes: [v], pricing: p)

        #expect(items.count == 1)
        #expect(items[0].id == "volume-1")
        #expect(items[0].kind == .volume)
        #expect(items[0].createdAt == created)
        guard case .monthlyFlat(let net) = items[0].pricing else {
            Issue.record("expected monthlyFlat pricing")
            return
        }
        // 10 GB * 0.04/GB = 0.40
        #expect(net == Decimal(string: "0.40")!)
    }

    @Test func volumeSkippedWhenNoPerGBPriceAvailable() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let v = Self.volume(created: created, size: 10)
        let p = Self.pricing(volumePerGBMonth: nil)

        let items = CostItemBuilder.items(volumes: [v], pricing: p)

        #expect(items.isEmpty)
    }

    @Test func multipleVolumesEachPricedIndependently() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let a = Self.volume(id: 1, name: "data-1", created: created, size: 10)
        let b = Self.volume(id: 2, name: "data-2", created: created, size: 100)
        let p = Self.pricing(volumePerGBMonth: PriceValue(net: "0.0400", gross: "0.0476"))

        let items = CostItemBuilder.items(volumes: [a, b], pricing: p)

        #expect(items.count == 2)
        guard case .monthlyFlat(let netA) = items[0].pricing, case .monthlyFlat(let netB) = items[1].pricing else {
            Issue.record("expected monthlyFlat pricing")
            return
        }
        #expect(netA == Decimal(string: "0.40")!)
        #expect(netB == Decimal(string: "4.00")!)
    }

    // MARK: - Primary IPs

    private static func primaryIP(
        id: Int = 1,
        name: String = "server-1-ipv4",
        created: Date,
        type: IPAddressType = .ipv4,
        locationName: String = "fsn1"
    ) -> PrimaryIP {
        PrimaryIP(
            id: id, name: name, ip: "1.2.3.4", type: type,
            assigneeID: nil, assigneeType: nil, autoDelete: false, blocked: false,
            created: created, datacenter: datacenter(location: locationName),
            dnsPtr: [], labels: [:], protection: DeleteProtection(delete: false)
        )
    }

    @Test func primaryIPMatchesByTypeAndLocation() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let fsn1 = ServerTypePrice(location: "fsn1", hourly: PriceValue(net: "0.0010", gross: "0.00119"), monthly: PriceValue(net: "0.50", gross: "0.595"))
        let hel1 = ServerTypePrice(location: "hel1", hourly: PriceValue(net: "0.0012", gross: "0.00143"), monthly: PriceValue(net: "0.60", gross: "0.714"))
        let ip = Self.primaryIP(created: created, type: .ipv4, locationName: "fsn1")
        let p = Self.pricing(primaryIPs: [PricingPrimaryIP(type: "ipv4", prices: [hel1, fsn1])])

        let items = CostItemBuilder.items(primaryIPs: [ip], pricing: p)

        #expect(items.count == 1)
        #expect(items[0].id == "primary-ip-1")
        #expect(items[0].kind == .primaryIP)
        guard case .monthlyFlat(let net) = items[0].pricing else {
            Issue.record("expected monthlyFlat pricing")
            return
        }
        #expect(net == Decimal(string: "0.50")!)
    }

    @Test func primaryIPFallsBackToFirstPriceForTypeWhenLocationMissing() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let hel1 = ServerTypePrice(location: "hel1", hourly: PriceValue(net: "0.0012", gross: "0.00143"), monthly: PriceValue(net: "0.60", gross: "0.714"))
        let ip = Self.primaryIP(created: created, type: .ipv4, locationName: "nbg1")
        let p = Self.pricing(primaryIPs: [PricingPrimaryIP(type: "ipv4", prices: [hel1])])

        let items = CostItemBuilder.items(primaryIPs: [ip], pricing: p)

        #expect(items.count == 1)
        guard case .monthlyFlat(let net) = items[0].pricing else {
            Issue.record("expected monthlyFlat pricing")
            return
        }
        #expect(net == Decimal(string: "0.60")!)
    }

    @Test func primaryIPSkippedWhenTypeNotInPricingList() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let ip = Self.primaryIP(created: created, type: .ipv6, locationName: "fsn1")
        let p = Self.pricing(primaryIPs: [])

        let items = CostItemBuilder.items(primaryIPs: [ip], pricing: p)

        #expect(items.isEmpty)
    }

    // MARK: - Load balancers

    private static func loadBalancer(
        id: Int = 1,
        name: String = "web-lb",
        created: Date,
        locationName: String = "fsn1",
        typePrices: [ServerTypePrice]
    ) -> LoadBalancer {
        LoadBalancer(
            id: id, name: name,
            publicNet: LBPublicNet(enabled: true, ipv4: nil, ipv6: nil),
            privateNet: [],
            location: location(locationName),
            loadBalancerType: LoadBalancerType(id: 1, name: "lb11", description: "LB11", maxConnections: 20000, maxServices: 5, maxTargets: 25, prices: typePrices),
            protection: LBProtection(delete: false),
            labels: [:],
            created: created,
            services: [],
            targets: [],
            algorithm: LBAlgorithm(type: .roundRobin),
            outgoingTraffic: nil,
            ingoingTraffic: nil,
            includedTraffic: nil
        )
    }

    @Test func loadBalancerUsesEmbeddedTypePricesForItsLocation() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let fsn1 = ServerTypePrice(location: "fsn1", hourly: PriceValue(net: "0.0060", gross: "0.00714"), monthly: PriceValue(net: "5.39", gross: "6.41"))
        let hel1 = ServerTypePrice(location: "hel1", hourly: PriceValue(net: "0.0070", gross: "0.00833"), monthly: PriceValue(net: "6.00", gross: "7.14"))
        let lb = Self.loadBalancer(created: created, locationName: "fsn1", typePrices: [hel1, fsn1])
        let p = Self.pricing()

        let items = CostItemBuilder.items(loadBalancers: [lb], pricing: p)

        #expect(items.count == 1)
        #expect(items[0].id == "load-balancer-1")
        #expect(items[0].kind == .loadBalancer)
        guard case .hourly(let net, let cap) = items[0].pricing else {
            Issue.record("expected hourly pricing")
            return
        }
        #expect(net == Decimal(string: "0.0060")!)
        #expect(cap == Decimal(string: "5.39")!)
    }

    @Test func loadBalancerFallsBackToFirstPriceWhenLocationMissing() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let hel1 = ServerTypePrice(location: "hel1", hourly: PriceValue(net: "0.0070", gross: "0.00833"), monthly: PriceValue(net: "6.00", gross: "7.14"))
        let lb = Self.loadBalancer(created: created, locationName: "nbg1", typePrices: [hel1])
        let p = Self.pricing()

        let items = CostItemBuilder.items(loadBalancers: [lb], pricing: p)

        #expect(items.count == 1)
        guard case .hourly(let net, _) = items[0].pricing else {
            Issue.record("expected hourly pricing")
            return
        }
        #expect(net == Decimal(string: "0.0070")!)
    }

    @Test func loadBalancerSkippedWhenNoPricesEmbedded() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let lb = Self.loadBalancer(created: created, typePrices: [])
        let p = Self.pricing()

        let items = CostItemBuilder.items(loadBalancers: [lb], pricing: p)

        #expect(items.isEmpty)
    }

    // MARK: - End-to-end

    @Test func allResourceKindsFeedIntoCostEngineEndToEnd() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let v = Self.volume(created: created, size: 10)
        let fsn1IP = ServerTypePrice(location: "fsn1", hourly: PriceValue(net: "0.0010", gross: "0.00119"), monthly: PriceValue(net: "0.50", gross: "0.595"))
        let ip = Self.primaryIP(created: created, type: .ipv4, locationName: "fsn1")
        let fsn1LB = ServerTypePrice(location: "fsn1", hourly: PriceValue(net: "0.0060", gross: "0.00714"), monthly: PriceValue(net: "5.39", gross: "6.41"))
        let lb = Self.loadBalancer(created: created, locationName: "fsn1", typePrices: [fsn1LB])

        let p = Self.pricing(
            volumePerGBMonth: PriceValue(net: "0.0400", gross: "0.0476"),
            primaryIPs: [PricingPrimaryIP(type: "ipv4", prices: [fsn1IP])]
        )

        var items = CostItemBuilder.items(volumes: [v], pricing: p)
        items += CostItemBuilder.items(primaryIPs: [ip], pricing: p)
        items += CostItemBuilder.items(loadBalancers: [lb], pricing: p)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let now = Date(timeIntervalSince1970: 1_700_100_000)

        let summary = CostEngine.summary(items: items, now: now, calendar: calendar, currency: p.currency)

        #expect(summary.perItem.count == 3)
        #expect(summary.currency == "EUR")
        #expect(summary.projectedMonthTotal > 0)
        #expect(Set(summary.perItem.map(\.kind)) == [.volume, .primaryIP, .loadBalancer])
    }
}
