import Foundation
import HetznerKit

/// The single seam between `HetznerKit.RobotAPI`'s wire models
/// (`OrderingModels.swift`) and this feature's own domain types
/// (`OrderModels.swift`). Every other file in `Ordering/` only ever sees the
/// local types — if Robot's product shape changes, this is the only file
/// that needs to change.
enum RobotOrderingMapping {
    static func listing(_ product: RobotMarketProduct) -> MarketListing {
        let net = decimal(product.price)
        // `RobotMarketProduct` only carries a gross variant of the recurring
        // price (`priceVAT`) — there's no separate gross figure for the
        // one-time setup fee, so the same net→gross ratio is applied to it.
        let gross = product.priceVAT.map { decimal($0) } ?? net
        let setupNet = decimal(product.priceSetup)
        let vatMultiplier: Decimal = net > 0 ? gross / net : 1
        let nextReduceDate = product.nextReduce.map { Date().addingTimeInterval(TimeInterval($0)) }

        return MarketListing(
            id: product.id,
            name: product.name,
            cpu: product.cpu,
            cpuBenchmark: product.cpuBenchmark,
            memoryGB: product.memorySize,
            hddSummary: product.hddText ?? "\(product.hddSize) GB",
            hddTB: Double(product.hddSize) / 1000,
            monthlyNet: net,
            monthlyGross: gross,
            setupNet: setupNet,
            setupGross: setupNet * vatMultiplier,
            currency: "EUR",
            fixedPrice: product.fixedPrice ?? false,
            nextReduceDate: nextReduceDate,
            datacenter: product.datacenter,
            descriptionLines: product.description,
            traffic: product.traffic
        )
    }

    static func listing(_ product: RobotProduct) -> StandardListing {
        let prices = product.prices.map { entry in
            StandardLocationPrice(
                location: entry.location,
                monthlyNet: entry.price.netDecimal ?? 0,
                monthlyGross: entry.price.grossDecimal ?? 0,
                setupNet: entry.priceSetup.netDecimal ?? 0,
                setupGross: entry.priceSetup.grossDecimal ?? 0
            )
        }
        return StandardListing(
            id: product.id,
            name: product.name,
            descriptionLines: product.description,
            traffic: product.traffic,
            distOptions: product.dist,
            prices: prices,
            currency: "EUR"
        )
    }

    static func option(_ key: RobotSSHKey) -> SSHKeyOption {
        SSHKeyOption(fingerprint: key.fingerprint, name: key.name)
    }

    static func summary(_ transaction: RobotTransaction) -> TransactionSummary {
        TransactionSummary(
            id: transaction.id,
            date: transaction.dateValue ?? .distantPast,
            status: status(transaction.status),
            productName: transaction.product?.name ?? transaction.product?.id ?? "Dedicated Server",
            serverNumber: transaction.serverNumber
        )
    }

    private static func status(_ status: RobotTransactionStatus) -> TransactionSummary.Status {
        switch status {
        case .inProcess: .inProcess
        case .ready: .ready
        case .cancelled: .cancelled
        case .unknown: .unknown
        }
    }

    /// Robot returns money as EUR strings (`"39.0000"`) — parsed defensively,
    /// never force-unwrapped, per the M3 "parse carefully" convention.
    static func decimal(_ string: String?) -> Decimal {
        guard let string, let value = Decimal(string: string) else { return 0 }
        return value
    }
}
