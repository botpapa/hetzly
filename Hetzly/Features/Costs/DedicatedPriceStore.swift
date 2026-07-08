import Foundation
import Observation

/// A manually entered monthly price for one Robot dedicated server, keyed by
/// `RobotServer.serverNumber` — Hetzner's Robot Webservice has no pricing
/// endpoint for servers you already own (only for ordering new ones), so
/// there is no way to fetch what a running dedicated server actually costs.
struct DedicatedPriceEntry: Codable, Identifiable, Sendable, Equatable {
    let serverNumber: Int
    var monthlyPrice: Decimal
    var note: String?

    var id: Int { serverNumber }

    init(serverNumber: Int, monthlyPrice: Decimal, note: String? = nil) {
        self.serverNumber = serverNumber
        self.monthlyPrice = monthlyPrice
        self.note = note
    }
}

/// `UserDefaults`-backed store for manually entered dedicated-server prices,
/// mirroring `ManualCostStore`'s shape exactly (same rationale: a handful of
/// rows, not secret, no need for Keychain or SwiftData). Distinct storage
/// key and distinct entry shape (keyed by `serverNumber` rather than a
/// random `UUID`) because these entries attach to a specific, auto-listed
/// Robot server rather than a free-form named cost.
///
/// Owned by the Costs feature — `CostsView` instantiates one directly,
/// exactly like `ManualCostStore`.
@MainActor
@Observable
final class DedicatedPriceStore {
    private(set) var entries: [DedicatedPriceEntry] = []

    @ObservationIgnored
    private let defaults: UserDefaults

    private static let storageKey = "com.hetzly.costs.dedicatedPrices"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// The stored price for a given Robot server, if one has been set.
    func price(for serverNumber: Int) -> DedicatedPriceEntry? {
        entries.first { $0.serverNumber == serverNumber }
    }

    /// Sets (inserting or overwriting) the price for a server.
    func setPrice(serverNumber: Int, monthlyPrice: Decimal, note: String?) {
        if let index = entries.firstIndex(where: { $0.serverNumber == serverNumber }) {
            entries[index].monthlyPrice = monthlyPrice
            entries[index].note = note
        } else {
            entries.append(DedicatedPriceEntry(serverNumber: serverNumber, monthlyPrice: monthlyPrice, note: note))
        }
        persist()
    }

    /// Clears a server's price — it goes back to being an unpriced "Set
    /// price" row and drops out of cost totals until priced again.
    func removePrice(for serverNumber: Int) {
        entries.removeAll { $0.serverNumber == serverNumber }
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey) else { return }
        entries = (try? JSONDecoder().decode([DedicatedPriceEntry].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
