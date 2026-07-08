import XCTest
@testable import Hetzly

@MainActor
final class CloudServerPriceStoreTests: XCTestCase {
    // nonisolated(unsafe): UserDefaults is thread-safe; the nonisolated
    // setUp/tearDown overrides and the MainActor tests never race.
    private nonisolated(unsafe) var defaults: UserDefaults!
    private nonisolated let suiteName = "com.hetzly.tests.CloudServerPriceStoreTests"

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
        let store = CloudServerPriceStore(defaults: defaults)
        XCTAssertNil(store.price(for: 12345))

        store.setPrice(serverNumber: 12345, monthlyPrice: Decimal(string: "25.49")!, note: "Grandfathered CX21")

        XCTAssertEqual(store.price(for: 12345), Decimal(string: "25.49"))
        XCTAssertEqual(store.entries.first?.note, "Grandfathered CX21")

        // A second store instance backed by the same `UserDefaults` suite
        // must read back what the first one persisted — the actual
        // round-trip through `UserDefaults`, not just in-memory state.
        let reloaded = CloudServerPriceStore(defaults: defaults)
        XCTAssertEqual(reloaded.price(for: 12345), Decimal(string: "25.49"))
        XCTAssertEqual(reloaded.entries.first?.note, "Grandfathered CX21")
    }

    func test_setPrice_overwritesExistingEntry() {
        let store = CloudServerPriceStore(defaults: defaults)
        store.setPrice(serverNumber: 1, monthlyPrice: Decimal(string: "10.00")!, note: "first")
        store.setPrice(serverNumber: 1, monthlyPrice: Decimal(string: "20.00")!, note: "second")

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.price(for: 1), Decimal(string: "20.00"))
        XCTAssertEqual(store.entries.first?.note, "second")
    }

    func test_removePrice_clearsEntryAndPersists() {
        let store = CloudServerPriceStore(defaults: defaults)
        store.setPrice(serverNumber: 7, monthlyPrice: Decimal(string: "99.00")!, note: nil)
        XCTAssertNotNil(store.price(for: 7))

        store.removePrice(for: 7)
        XCTAssertNil(store.price(for: 7))

        let reloaded = CloudServerPriceStore(defaults: defaults)
        XCTAssertNil(reloaded.price(for: 7))
    }

    func test_multipleEntries_areIndependentlyAddressable() {
        let store = CloudServerPriceStore(defaults: defaults)
        store.setPrice(serverNumber: 1, monthlyPrice: Decimal(string: "10.00")!, note: nil)
        store.setPrice(serverNumber: 2, monthlyPrice: Decimal(string: "20.00")!, note: nil)

        XCTAssertEqual(store.price(for: 1), Decimal(string: "10.00"))
        XCTAssertEqual(store.price(for: 2), Decimal(string: "20.00"))
        XCTAssertEqual(store.entries.count, 2)
    }

    func test_price_returnsNilForUnknownServer() {
        let store = CloudServerPriceStore(defaults: defaults)
        store.setPrice(serverNumber: 1, monthlyPrice: Decimal(string: "10.00")!, note: nil)

        XCTAssertNil(store.price(for: 999))
    }
}
