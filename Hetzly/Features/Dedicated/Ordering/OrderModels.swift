import Foundation

/// This feature's own display-ready domain types for the ordering flow.
///
/// Every view in `Ordering/` is written against these — never against
/// `HetznerKit`'s wire models (`RobotProduct`, `RobotMarketProduct`,
/// `RobotSSHKey`, `RobotTransaction`) directly. `RobotOrderingMapping.swift`
/// is the single seam that converts between the two (also isolating the
/// EUR-string → `Decimal` parsing to one place), and every `#Preview` in
/// this directory builds these types directly rather than constructing
/// RobotAPI's wire models.

/// One SSH key as offered to the "authorized keys" multi-select. Robot
/// identifies keys by fingerprint on the wire (`authorized_key[]` takes
/// fingerprints, per CONTRACTS.md's `RobotServerOrder`/`RobotMarketOrder`).
struct SSHKeyOption: Identifiable, Sendable, Hashable {
    let fingerprint: String
    let name: String
    var id: String { fingerprint }
}

/// A Server Market (auction) listing: fixed, as-is hardware sitting in a
/// specific datacenter, sold at a reduced price until its next reduction.
/// Market orders are placed as-is — Robot's `RobotMarketOrder` has no
/// location or distribution parameter, so this listing carries neither.
struct MarketListing: Identifiable, Sendable, Hashable {
    /// Also `RobotMarketOrder.productID` — Robot's market product ids are
    /// wire strings (numeric-looking, e.g. `"234323"`), not integers.
    let id: String
    let name: String
    let cpu: String
    let cpuBenchmark: Int?
    let memoryGB: Int
    let hddSummary: String
    /// Parsed from Robot's HDD size (reported in GB) for the "min HDD TB" filter.
    let hddTB: Double
    let monthlyNet: Decimal
    let monthlyGross: Decimal
    let setupNet: Decimal
    let setupGross: Decimal
    let currency: String
    let fixedPrice: Bool
    let nextReduceDate: Date?
    let datacenter: String?
    let descriptionLines: [String]
    let traffic: String

    /// `true` when the next price reduction is close enough to be worth
    /// flagging inline — display-only, no live countdown/timer per the M3
    /// no-background-polling constraint.
    func isNextReduceSoon(now: Date = Date()) -> Bool {
        guard let nextReduceDate else { return false }
        let interval = nextReduceDate.timeIntervalSince(now)
        return interval > 0 && interval < 6 * 3600
    }
}

/// One location's price for a `StandardListing` — Robot prices standard
/// products per-location (`RobotProduct.prices: [RobotProductPrice]`), so
/// the monthly/setup figures aren't flat like a market listing's.
struct StandardLocationPrice: Hashable, Sendable {
    let location: String
    let monthlyNet: Decimal
    let monthlyGross: Decimal
    let setupNet: Decimal
    let setupGross: Decimal
}

/// A Standard (configurable) product: a server type Hetzner builds to order,
/// sold at a location-dependent monthly price.
struct StandardListing: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let descriptionLines: [String]
    let traffic: String
    let distOptions: [String]
    let prices: [StandardLocationPrice]
    let currency: String

    var locationOptions: [String] { prices.map(\.location) }

    /// The cheapest available location's price — used as the representative
    /// figure in list rows, before a location is chosen in the detail view.
    var cheapestPrice: StandardLocationPrice? {
        prices.min { $0.monthlyNet < $1.monthlyNet }
    }

    /// The price for `location`, falling back to the cheapest available one
    /// when `location` is `nil` or not sold there.
    func price(at location: String?) -> StandardLocationPrice? {
        guard let location, let match = prices.first(where: { $0.location == location }) else {
            return cheapestPrice
        }
        return match
    }
}

/// What a listing resolves to once the user has picked SSH keys (and, for
/// standard products, dist/location) — everything the review screen needs to
/// restate, and everything `OrderFlowViewModel.placeOrder` needs to build
/// the wire request.
enum OrderDraft: Hashable {
    case market(MarketListing, sshKeys: [SSHKeyOption])
    case standard(StandardListing, price: StandardLocationPrice, dist: String?, sshKeys: [SSHKeyOption])

    var displayName: String {
        switch self {
        case .market(let listing, _): listing.name
        case .standard(let listing, _, _, _): listing.name
        }
    }

    var monthlyNet: Decimal {
        switch self {
        case .market(let listing, _): listing.monthlyNet
        case .standard(_, let price, _, _): price.monthlyNet
        }
    }

    var monthlyGross: Decimal {
        switch self {
        case .market(let listing, _): listing.monthlyGross
        case .standard(_, let price, _, _): price.monthlyGross
        }
    }

    var setupNet: Decimal {
        switch self {
        case .market(let listing, _): listing.setupNet
        case .standard(_, let price, _, _): price.setupNet
        }
    }

    var setupGross: Decimal {
        switch self {
        case .market(let listing, _): listing.setupGross
        case .standard(_, let price, _, _): price.setupGross
        }
    }

    var currency: String {
        switch self {
        case .market(let listing, _): listing.currency
        case .standard(let listing, _, _, _): listing.currency
        }
    }

    var sshKeys: [SSHKeyOption] {
        switch self {
        case .market(_, let keys): keys
        case .standard(_, _, _, let keys): keys
        }
    }

    var dist: String? {
        switch self {
        case .market: nil
        case .standard(_, _, let dist, _): dist
        }
    }

    var location: String? {
        switch self {
        case .market: nil
        case .standard(_, let price, _, _): price.location
        }
    }
}

/// A placed-or-past order transaction, restated for `TransactionsListView`
/// and the post-placement result screen.
struct TransactionSummary: Identifiable, Sendable, Hashable {
    enum Status: Hashable, Sendable {
        case inProcess
        case ready
        case cancelled
        case unknown

        var displayText: String {
            switch self {
            case .inProcess: "In Process"
            case .ready: "Ready"
            case .cancelled: "Cancelled"
            case .unknown: "Unknown"
            }
        }

        var resourceStatus: ResourceStatus {
            switch self {
            case .inProcess: .transitioning
            case .ready: .running
            case .cancelled: .off
            case .unknown: .unknown
            }
        }
    }

    let id: String
    let date: Date
    let status: Status
    let productName: String
    let serverNumber: Int?
}

/// Why order placement failed, in a shape the result screen can render
/// distinct copy for — Robot's 403-with-ordering-disabled case gets a full
/// explainer card rather than a generic error string.
///
/// `message`'s `isAmbiguous` flag distinguishes a clean API rejection (the
/// request definitely reached Hetzner and was definitely refused — safe to
/// resubmit with the same arming) from a transport-level/timeout failure
/// (the request may or may not have landed — `OrderFlowViewModel.retryPlacement()`
/// forces the user to re-arm before resubmitting, and `OrderPlacementResultView`
/// shows a warning pointing at Order History instead of just "Try Again").
enum OrderPlacementError: Equatable {
    case orderingDisabled
    case message(String, isAmbiguous: Bool = false)
}

// MARK: - Market filtering & sorting

struct MarketFilter: Equatable {
    var priceCeiling: Decimal?
    var minCPUBenchmark: Int?
    var minRAMGB: Int?
    var minHDDTB: Double?

    var isActive: Bool {
        priceCeiling != nil || minCPUBenchmark != nil || minRAMGB != nil || minHDDTB != nil
    }

    func matches(_ listing: MarketListing) -> Bool {
        if let priceCeiling, listing.monthlyNet > priceCeiling { return false }
        if let minCPUBenchmark {
            guard let benchmark = listing.cpuBenchmark, benchmark >= minCPUBenchmark else { return false }
        }
        if let minRAMGB, listing.memoryGB < minRAMGB { return false }
        if let minHDDTB, listing.hddTB < minHDDTB { return false }
        return true
    }
}

enum MarketSort: String, CaseIterable, Identifiable, Sendable {
    case priceAscending, priceDescending, ramDescending, nextReduceSoonest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .priceAscending: "Price: Low to High"
        case .priceDescending: "Price: High to Low"
        case .ramDescending: "RAM"
        case .nextReduceSoonest: "Next Reduce"
        }
    }

    func sort(_ listings: [MarketListing]) -> [MarketListing] {
        switch self {
        case .priceAscending:
            listings.sorted { $0.monthlyNet < $1.monthlyNet }
        case .priceDescending:
            listings.sorted { $0.monthlyNet > $1.monthlyNet }
        case .ramDescending:
            listings.sorted { $0.memoryGB > $1.memoryGB }
        case .nextReduceSoonest:
            listings.sorted {
                switch ($0.nextReduceDate, $1.nextReduceDate) {
                case (nil, nil): false
                case (nil, _): false
                case (_, nil): true
                case (let a?, let b?): a < b
                }
            }
        }
    }
}

/// Formats `Decimal` money amounts using Robot's pricing currency code. Kept
/// local to this feature (each wave-B/C/M3 feature owns its own copy rather
/// than depending on another worker's in-flight module — see
/// `Features/CreateServer/CurrencyFormat.swift` for the precedent).
enum OrderCurrencyFormat {
    static func string(_ amount: Decimal, currencyCode: String, fractionDigits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(currencyCode) \(amount)"
    }
}
