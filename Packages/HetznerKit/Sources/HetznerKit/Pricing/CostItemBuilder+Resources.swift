import Foundation

/// Adapts the remaining billable CloudAPI resources (volumes, primary IPs,
/// load balancers) into `CostItem`s, following the same pattern as
/// `CostItemBuilder.items(servers:pricing:)`: these are the only places in
/// the Pricing module that know about these CloudAPI shapes.
extension CostItemBuilder {
    /// Block Storage volumes are billed as a flat monthly amount per
    /// provisioned GB (no hourly/capped billing, unlike servers).
    public static func items(volumes: [Volume], pricing: Pricing) -> [CostItem] {
        guard let perGBMonth = pricing.volumePerGBMonth?.netDecimal else { return [] }

        return volumes.map { volume in
            CostItem(
                id: "volume-\(volume.id)",
                name: volume.name,
                kind: .volume,
                pricing: .monthlyFlat(net: perGBMonth * Decimal(volume.size)),
                createdAt: volume.created
            )
        }
    }

    /// Primary IPs are billed as a flat monthly amount, matched by IP type
    /// (`ipv4`/`ipv6`) and then by the datacenter's location, falling back
    /// to the type's first listed price if no exact location match exists.
    public static func items(primaryIPs: [PrimaryIP], pricing: Pricing) -> [CostItem] {
        var result: [CostItem] = []
        result.reserveCapacity(primaryIPs.count)

        for primaryIP in primaryIPs {
            guard let price = matchingPrice(for: primaryIP, pricing: pricing),
                  let monthlyNet = price.monthly.netDecimal
            else { continue }

            result.append(
                CostItem(
                    id: "primary-ip-\(primaryIP.id)",
                    name: primaryIP.name,
                    kind: .primaryIP,
                    pricing: .monthlyFlat(net: monthlyNet),
                    createdAt: primaryIP.created
                )
            )
        }

        return result
    }

    /// Load Balancers are billed hourly, capped at the equivalent monthly
    /// price, exactly like servers. Prices are read from the load balancer's
    /// own embedded `loadBalancerType.prices` (mirroring how a server's own
    /// `serverType.prices` is the fallback for the canonical `/pricing`
    /// list) since `Pricing` does not currently surface a top-level
    /// `load_balancer_types` price list to fall back to.
    public static func items(loadBalancers: [LoadBalancer], pricing: Pricing) -> [CostItem] {
        var result: [CostItem] = []
        result.reserveCapacity(loadBalancers.count)

        for loadBalancer in loadBalancers {
            guard let price = matchingPrice(for: loadBalancer),
                  let hourlyNet = price.hourly.netDecimal
            else { continue }
            let monthlyNet = price.monthly.netDecimal

            result.append(
                CostItem(
                    id: "load-balancer-\(loadBalancer.id)",
                    name: loadBalancer.name,
                    kind: .loadBalancer,
                    pricing: .hourly(net: hourlyNet, monthlyCap: monthlyNet),
                    createdAt: loadBalancer.created
                )
            )
        }

        return result
    }

    // MARK: - Price matching

    /// Finds this primary IP's price by matching its `type` against
    /// `Pricing.primaryIPs`, then its datacenter's location against that
    /// type's price list, falling back to the first listed price for the
    /// type if no exact location match exists.
    private static func matchingPrice(for primaryIP: PrimaryIP, pricing: Pricing) -> ServerTypePrice? {
        let prices = pricing.primaryIPs.first { $0.type == primaryIP.type.rawValue }?.prices
        guard let prices, !prices.isEmpty else { return nil }
        return prices.first { $0.location == primaryIP.datacenter.location.name } ?? prices.first
    }

    /// Finds this load balancer's price for its own location, matching
    /// `location.name` against the embedded `loadBalancerType.prices`,
    /// falling back to the first listed price if no exact match exists.
    private static func matchingPrice(for loadBalancer: LoadBalancer) -> ServerTypePrice? {
        let prices = loadBalancer.loadBalancerType.prices
        guard !prices.isEmpty else { return nil }
        return prices.first { $0.location == loadBalancer.location.name } ?? prices.first
    }
}
