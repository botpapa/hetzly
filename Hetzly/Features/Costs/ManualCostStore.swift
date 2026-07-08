import Foundation
import Observation

/// `UserDefaults`-backed store for manually entered fixed costs (mainly
/// dedicated servers — see `ManualCostEntry`). Not secret data, so a plain
/// JSON blob in `UserDefaults` is sufficient; there's no need for Keychain
/// or a SwiftData model for what's typically a handful of rows.
///
/// Owned by the Costs feature (not `AppContainer`) since dedicated-server
/// pricing is Costs-specific state, not shared app-wide dependency-injection
/// surface — `CostsView` instantiates one directly.
@MainActor
@Observable
final class ManualCostStore {
    private(set) var entries: [ManualCostEntry] = []

    @ObservationIgnored
    private let defaults: UserDefaults

    private static let storageKey = "com.hetzly.costs.manualEntries"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    @discardableResult
    func add(name: String, monthlyPrice: Decimal, note: String?) -> ManualCostEntry {
        let entry = ManualCostEntry(name: name, monthlyPrice: monthlyPrice, note: note)
        entries.append(entry)
        persist()
        return entry
    }

    func update(_ id: ManualCostEntry.ID, name: String, monthlyPrice: Decimal, note: String?) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].name = name
        entries[index].monthlyPrice = monthlyPrice
        entries[index].note = note
        persist()
    }

    func remove(_ entry: ManualCostEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey) else { return }
        entries = (try? JSONDecoder().decode([ManualCostEntry].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
