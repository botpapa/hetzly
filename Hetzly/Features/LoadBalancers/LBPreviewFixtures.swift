import Foundation
import HetznerKit

/// Preview-only mock data for the Load Balancers feature. No network access —
/// every `#Preview` in this directory renders from these fixtures.
enum LBPreviewFixtures {
    static let now = Date()

    static let location = Location(
        id: 1,
        name: "nbg1",
        description: "Nuremberg DC Park 1",
        country: "DE",
        city: "Nuremberg",
        latitude: 49.452102,
        longitude: 11.076665,
        networkZone: "eu-central"
    )

    static let lb11 = LoadBalancerType(
        id: 1,
        name: "lb11",
        description: "LB11",
        maxConnections: 10_000,
        maxServices: 5,
        maxTargets: 25,
        prices: [
            ServerTypePrice(
                location: "nbg1",
                hourly: PriceValue(net: "0.0090", gross: "0.0107"),
                monthly: PriceValue(net: "5.39", gross: "6.41")
            ),
        ]
    )

    static let lb21 = LoadBalancerType(
        id: 2,
        name: "lb21",
        description: "LB21",
        maxConnections: 20_000,
        maxServices: 15,
        maxTargets: 75,
        prices: [
            ServerTypePrice(
                location: "nbg1",
                hourly: PriceValue(net: "0.0299", gross: "0.0356"),
                monthly: PriceValue(net: "17.99", gross: "21.41")
            ),
        ]
    )

    static let httpsService = LBService(
        protocol: .https,
        listenPort: 443,
        destinationPort: 8080,
        proxyprotocol: false,
        http: LBServiceHTTP(
            cookieName: "HCLBSTICKY",
            cookieLifetime: 300,
            certificates: [7],
            redirectHTTP: true,
            stickySessions: true
        ),
        healthCheck: LBHealthCheck(
            protocol: .http,
            port: 8080,
            interval: 15,
            timeout: 10,
            retries: 3,
            http: LBHealthCheckHTTP(domain: nil, path: "/healthz", response: nil, statusCodes: nil, tls: false)
        )
    )

    static let tcpService = LBService(
        protocol: .tcp,
        listenPort: 5_432,
        destinationPort: 5_432,
        proxyprotocol: false,
        http: nil,
        healthCheck: LBHealthCheck(protocol: .tcp, port: 5_432, interval: 15, timeout: 10, retries: 3, http: nil)
    )

    static let loadBalancer = LoadBalancer(
        id: 7,
        name: "web-lb",
        publicNet: LBPublicNet(
            enabled: true,
            ipv4: LBPublicNetIPv4(ip: "167.233.10.11", dnsPtr: "static.11.10.233.167.clients.your-server.de"),
            ipv6: LBPublicNetIPv6(ip: "2a01:4f8:1c1f::1", dnsPtr: nil)
        ),
        privateNet: [],
        location: location,
        loadBalancerType: lb11,
        protection: LBProtection(delete: false),
        labels: [:],
        created: now.addingTimeInterval(-14 * 24 * 3_600),
        services: [httpsService, tcpService],
        targets: [
            LBTarget(
                type: .server,
                server: LBTargetServer(id: 42),
                labelSelector: nil,
                ip: nil,
                usePrivateIP: false,
                healthStatus: [
                    LBTargetHealthStatus(listenPort: 443, status: .healthy),
                    LBTargetHealthStatus(listenPort: 5_432, status: .healthy),
                ]
            ),
            LBTarget(
                type: .server,
                server: LBTargetServer(id: 43),
                labelSelector: nil,
                ip: nil,
                usePrivateIP: false,
                healthStatus: [
                    LBTargetHealthStatus(listenPort: 443, status: .unhealthy),
                    LBTargetHealthStatus(listenPort: 5_432, status: .healthy),
                ]
            ),
            LBTarget(
                type: .labelSelector,
                server: nil,
                labelSelector: LBTargetLabelSelector(selector: "role=web"),
                ip: nil,
                usePrivateIP: nil,
                healthStatus: nil
            ),
        ],
        algorithm: LBAlgorithm(type: .roundRobin),
        outgoingTraffic: 12_884_901_888,
        ingoingTraffic: 4_294_967_296,
        includedTraffic: 21_990_232_555_520
    )

    static let metrics: ServerMetrics = {
        let step: TimeInterval = 60
        let start = now.addingTimeInterval(-3_600)
        return ServerMetrics(
            start: start,
            end: now,
            step: step,
            series: [
                MetricsSeries(name: "open_connections", points: wave(start: start, step: step, base: 140, amplitude: 60)),
                MetricsSeries(name: "connections_per_second", points: wave(start: start, step: step, base: 32, amplitude: 20)),
                MetricsSeries(name: "requests_per_second", points: wave(start: start, step: step, base: 210, amplitude: 90)),
                MetricsSeries(name: "bandwidth.in", points: wave(start: start, step: step, base: 1_400_000, amplitude: 700_000)),
                MetricsSeries(name: "bandwidth.out", points: wave(start: start, step: step, base: 3_100_000, amplitude: 1_500_000)),
            ]
        )
    }()

    private static func wave(
        start: Date, step: TimeInterval, base: Double, amplitude: Double, count: Int = 60
    ) -> [(timestamp: Date, value: Double)] {
        (0..<count).map { index in
            let angle = Double(index) / Double(count) * 4 * .pi
            let value = max(0, base + amplitude * sin(angle))
            return (timestamp: start.addingTimeInterval(Double(index) * step), value: value)
        }
    }
}
