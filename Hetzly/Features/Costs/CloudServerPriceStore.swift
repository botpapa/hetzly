import Foundation
import Observation

/// A manually entered "what I actually pay" monthly price for one Cloud
/// server, keyed by `Server.id`. Hetzner's Cloud API has no per-server real
/// price either: `/servers/{id}` has no price field, and `/pricing` is
/// always *current list* pricing — so a server kept on a grandfathered or
/// promotional rate over-reports its cost when every cost total is computed
/// from list price alone (see memory `hetzner-no-per-server-price`). This
/// mirrors `DedicatedPriceStore` exactly, down to the `UserDefaults` JSON
/// storage shape — the same fix, applied to Cloud servers instead of Robot's
/// dedicated ones (which have no pricing API at all, whereas Cloud servers
/// have a price, just not necessarily the *right* one).
struct CloudServerPriceEntry: Codable, Identifiable, Sendable, Equatable {
    var serverNumber: Int
    var monthlyPrice: Decimal
    var note: String?

    var id: Int { serverNumber }
}

/// `UserDefaults`-backed store for manually entered Cloud-server "what I
/// pay" overrides, mirroring `DedicatedPriceStore`'s shape exactly. Owned by
/// the Costs feature — `CostsView` instantiates one directly — but reusable
/// from anywhere in the app target: `CloudServerPriceSheet` (Costs and the
/// server detail page both present it), `DashboardViewModel`, and
/// `ProjectDetailViewModel` all read a fresh instance to fold overrides into
/// their own cost math without any shared DI plumbing.
@MainActor
@Observable
final class CloudServerPriceStore {
    private(set) var entries: [CloudServerPriceEntry] = []

    @ObservationIgnored
    private let defaults: UserDefaults

    private static let storageKey = "com.hetzly.costs.cloudServerPrices"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// The stored override for a given Cloud server, if one has been set.
    func price(for serverNumber: Int) -> Decimal? {
        entries.first { $0.serverNumber == serverNumber }?.monthlyPrice
    }

    /// Sets (inserting or overwriting) the override for a server.
    func setPrice(serverNumber: Int, monthlyPrice: Decimal, note: String?) {
        if let index = entries.firstIndex(where: { $0.serverNumber == serverNumber }) {
            entries[index].monthlyPrice = monthlyPrice
            entries[index].note = note
        } else {
            entries.append(CloudServerPriceEntry(serverNumber: serverNumber, monthlyPrice: monthlyPrice, note: note))
        }
        persist()
    }

    /// Clears a server's override — every cost total falls back to Hetzner's
    /// current list price for that server's type + location again.
    func removePrice(for serverNumber: Int) {
        entries.removeAll { $0.serverNumber == serverNumber }
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey) else { return }
        entries = (try? JSONDecoder().decode([CloudServerPriceEntry].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
