import HetznerKit
import SwiftUI

/// Aggregate health across a load balancer's targets, driving the list row's
/// summary dot: green when every reported check is healthy, red when every
/// one is unhealthy, yellow when mixed, gray when no target reports health.
enum LBHealthSummary {
    case allHealthy
    case mixed
    case allUnhealthy
    case unknown

    init(targets: [LBTarget]) {
        let states = targets.flatMap { $0.healthStatus ?? [] }.map(\.status)
        let known = states.filter { $0 != .unknown }
        guard !known.isEmpty else {
            self = .unknown
            return
        }
        if known.allSatisfy({ $0 == .healthy }) {
            self = .allHealthy
        } else if known.allSatisfy({ $0 == .unhealthy }) {
            self = .allUnhealthy
        } else {
            self = .mixed
        }
    }

    var color: Color {
        switch self {
        case .allHealthy: HetzlyColors.statusRunning
        case .mixed: HetzlyColors.statusTransitioning
        case .allUnhealthy: HetzlyColors.statusError
        case .unknown: HetzlyColors.statusOff
        }
    }

    var label: String {
        switch self {
        case .allHealthy: "All targets healthy"
        case .mixed: "Some targets unhealthy"
        case .allUnhealthy: "All targets unhealthy"
        case .unknown: "Health unknown"
        }
    }
}

extension LBAlgorithmType {
    static let editableCases: [LBAlgorithmType] = [.roundRobin, .leastConnections]

    var displayName: String {
        switch self {
        case .roundRobin: "Round Robin"
        case .leastConnections: "Least Connections"
        case .unknown: "Unknown"
        }
    }
}

extension LBServiceProtocol {
    static let editableCases: [LBServiceProtocol] = [.tcp, .http, .https]

    var displayName: String {
        switch self {
        case .tcp: "TCP"
        case .http: "HTTP"
        case .https: "HTTPS"
        case .unknown: "Unknown"
        }
    }

    var isHTTPLike: Bool {
        self == .http || self == .https
    }
}

extension LBTarget {
    /// Display name for a target row; server names come from `servers`
    /// (resolved via `listServers()` by the detail view model).
    func displayName(servers: [Server]) -> String {
        switch type {
        case .server:
            guard let id = server?.id else { return "Server" }
            return servers.first { $0.id == id }?.name ?? "Server #\(id)"
        case .labelSelector:
            return labelSelector?.selector ?? "Label selector"
        case .ip:
            return ip?.ip ?? "IP target"
        case .unknown:
            return "Unknown target"
        }
    }

    var systemImage: String {
        switch type {
        case .server: "server.rack"
        case .labelSelector: "tag"
        case .ip: "number"
        case .unknown: "questionmark"
        }
    }
}

/// The monthly price line shown next to a `LoadBalancerType` in pickers,
/// e.g. "€5.39/mo". Prefers the price at `locationName`; falls back to the
/// first listed location.
enum LBTypePriceFormatter {
    static func monthly(for type: LoadBalancerType, locationName: String?) -> String? {
        let price = type.prices.first { $0.location == locationName } ?? type.prices.first
        guard let net = price?.monthly.netDecimal else { return nil }
        return "€\(net)/mo"
    }
}
