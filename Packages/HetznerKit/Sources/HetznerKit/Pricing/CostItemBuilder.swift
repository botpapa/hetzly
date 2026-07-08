import Foundation

/// Adapts CloudAPI models (`Server`, `Pricing`) into the pure `CostItem`
/// values `CostEngine` operates on. This is the one file in the Pricing
/// module that knows about CloudAPI shapes — the rest of the engine is fed
/// generic `CostItem`s and stays independent of them.
public enum CostItemBuilder {
    public static func items(servers: [Server], pricing: Pricing) -> [CostItem] {
        var result: [CostItem] = []
        result.reserveCapacity(servers.count * 2)

        for server in servers {
            guard let price = matchingPrice(for: server, pricing: pricing) else { continue }
            guard let hourlyNet = price.hourly.netDecimal else { continue }
            let monthlyNet = price.monthly.netDecimal

            result.append(
                CostItem(
                    id: "server-\(server.id)",
                    name: server.name,
                    kind: .server,
                    // Hetzner caps hourly billing at the equivalent monthly price.
                    pricing: .hourly(net: hourlyNet, monthlyCap: monthlyNet),
                    createdAt: server.created
                )
            )

            if server.backupWindow != nil, let backupItem = backupItem(for: server, monthlyNet: monthlyNet, pricing: pricing) {
                result.append(backupItem)
            }
        }

        return result
    }

    /// Finds this server's price for its own location, matching
    /// `datacenter.location.name` against `ServerTypePrice.location` and
    /// falling back to the first listed price if no exact match exists
    /// (e.g. a location renamed/retired between the server and pricing
    /// endpoints). Prefers the canonical `/pricing` list, falling back to
    /// the prices embedded on the server's own `serverType` if its type is
    /// missing from `pricing` for some reason.
    private static func matchingPrice(for server: Server, pricing: Pricing) -> ServerTypePrice? {
        let prices = pricing.serverTypes.first { $0.id == server.serverType.id }?.prices
            ?? server.serverType.prices
        guard !prices.isEmpty else { return nil }
        return prices.first { $0.location == server.datacenter.location.name } ?? prices.first
    }

    /// Hetzner's automated backups are billed as a percentage surcharge of
    /// the server's own monthly price.
    private static func backupItem(for server: Server, monthlyNet: Decimal?, pricing: Pricing) -> CostItem? {
        guard let monthlyNet,
              let percentageString = pricing.serverBackupPercentage,
              let percentage = Decimal(string: percentageString)
        else {
            return nil
        }
        let backupNet = (percentage / 100) * monthlyNet
        return CostItem(
            id: "backup-\(server.id)",
            name: "\(server.name) backups",
            kind: .backup,
            pricing: .monthlyFlat(net: backupNet),
            createdAt: server.created
        )
    }
}
