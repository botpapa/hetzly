import XCTest
@testable import Hetzly

@MainActor
final class DedicatedPriceStoreTests: XCTestCase {
    // nonisolated(unsafe): UserDefaults is thread-safe; the nonisolated
    // setUp/tearDown overrides and the MainActor tests never race.
    private nonisolated(unsafe) var defaults: UserDefaults!
    private nonisolated let suiteName = "com.hetzly.tests.DedicatedPriceStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func test_setPrice_roundTripsThroughUserDefaults() {
        let store = DedicatedPriceStore(defaults: defaults)
        XCTAssertNil(store.price(for: 12345))

        store.setPrice(serverNumber: 12345, monthlyPrice: Decimal(string: "49.99")!, note: "AX42")

        let entry = store.price(for: 12345)
        XCTAssertEqual(entry?.monthlyPrice, Decimal(string: "49.99"))
        XCTAssertEqual(entry?.note, "AX42")

        // A second store instance backed by the same `UserDefaults` suite
        // must read back what the first one persisted — the actual
        // round-trip through `UserDefaults`, not just in-memory state.
        let reloaded = DedicatedPriceStore(defaults: defaults)
        let reloadedEntry = reloaded.price(for: 12345)
        XCTAssertEqual(reloadedEntry?.monthlyPrice, Decimal(string: "49.99"))
        XCTAssertEqual(reloadedEntry?.note, "AX42")
    }

    func test_setPrice_overwritesExistingEntry() {
        let store = DedicatedPriceStore(defaults: defaults)
        store.setPrice(serverNumber: 1, monthlyPrice: Decimal(string: "10.00")!, note: "first")
        store.setPrice(serverNumber: 1, monthlyPrice: Decimal(string: "20.00")!, note: "second")

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.price(for: 1)?.monthlyPrice, Decimal(string: "20.00"))
        XCTAssertEqual(store.price(for: 1)?.note, "second")
    }

    func test_removePrice_clearsEntryAndPersists() {
        let store = DedicatedPriceStore(defaults: defaults)
        store.setPrice(serverNumber: 7, monthlyPrice: Decimal(string: "99.00")!, note: nil)
        XCTAssertNotNil(store.price(for: 7))

        store.removePrice(for: 7)
        XCTAssertNil(store.price(for: 7))

        let reloaded = DedicatedPriceStore(defaults: defaults)
        XCTAssertNil(reloaded.price(for: 7))
    }

    func test_multipleEntries_areIndependentlyAddressable() {
        let store = DedicatedPriceStore(defaults: defaults)
        store.setPrice(serverNumber: 1, monthlyPrice: Decimal(string: "10.00")!, note: nil)
        store.setPrice(serverNumber: 2, monthlyPrice: Decimal(string: "20.00")!, note: nil)

        XCTAssertEqual(store.price(for: 1)?.monthlyPrice, Decimal(string: "10.00"))
        XCTAssertEqual(store.price(for: 2)?.monthlyPrice, Decimal(string: "20.00"))
        XCTAssertEqual(store.entries.count, 2)
    }
}
