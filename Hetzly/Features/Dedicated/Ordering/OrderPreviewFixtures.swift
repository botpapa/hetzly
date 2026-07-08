import Foundation

/// Preview-only mock data for the ordering flow. No network access, and —
/// unlike a naive approach — never constructs `HetznerKit.RobotAPI`'s wire
/// models (`RobotProduct`, `RobotMarketProduct`, `RobotSSHKey`,
/// `RobotTransaction`) either: every `#Preview` in this directory renders
/// from this feature's own local domain types (`OrderModels.swift`), which
/// this worker fully controls, so these fixtures stay valid regardless of
/// RobotAPI's landing shape.
enum OrderPreviewFixtures {
    static let sshKeys: [SSHKeyOption] = [
        SSHKeyOption(fingerprint: "aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99", name: "personal-mac"),
        SSHKeyOption(fingerprint: "11:22:33:44:55:66:77:88:99:aa:bb:cc:dd:ee:ff:00", name: "work-laptop"),
    ]

    static let marketListings: [MarketListing] = [
        MarketListing(
            id: "234323", name: "DS 3000",
            cpu: "Intel Core i7-2600, 4 Cores", cpuBenchmark: 5417,
            memoryGB: 8, hddSummary: "2x 1.5 TB SATA", hddTB: 3.0,
            monthlyNet: 34.03, monthlyGross: 40.50, setupNet: 0, setupGross: 0,
            currency: "EUR", fixedPrice: false,
            nextReduceDate: Date().addingTimeInterval(3600 * 2), datacenter: "FSN1",
            descriptionLines: [
                "Intel Core i7-2600, 4 Cores",
                "8 GB DDR3 RAM",
                "2x 1.5 TB SATA HDD (Software-RAID 1)",
            ],
            traffic: "5 TB"
        ),
        MarketListing(
            id: "234512", name: "AX41-NVMe",
            cpu: "AMD Ryzen 5 3600, 6 Cores", cpuBenchmark: 15873,
            memoryGB: 64, hddSummary: "2x 512 GB NVMe SSD", hddTB: 1.0,
            monthlyNet: 54.28, monthlyGross: 64.59, setupNet: 39.90, setupGross: 47.48,
            currency: "EUR", fixedPrice: true,
            nextReduceDate: nil, datacenter: "NBG1",
            descriptionLines: [
                "AMD Ryzen 5 3600, 6 Cores",
                "64 GB DDR4 RAM",
                "2x 512 GB NVMe SSD (Software-RAID 1)",
            ],
            traffic: "unlimited"
        ),
    ]

    static let standardListings: [StandardListing] = [
        StandardListing(
            id: "EX44", name: "EX44",
            descriptionLines: [
                "Intel Core i5-13500",
                "64 GB DDR5 RAM",
                "2x 512 GB NVMe SSD",
            ],
            traffic: "unlimited",
            distOptions: ["Ubuntu 24.04", "Debian 12", "Rocky 9", "AlmaLinux 9"],
            prices: [
                StandardLocationPrice(location: "FSN1", monthlyNet: 39.00, monthlyGross: 46.41, setupNet: 0, setupGross: 0),
                StandardLocationPrice(location: "HEL1", monthlyNet: 39.00, monthlyGross: 46.41, setupNet: 0, setupGross: 0),
            ],
            currency: "EUR"
        ),
        StandardListing(
            id: "EX101", name: "EX101",
            descriptionLines: [
                "Intel Core i9-13900",
                "128 GB DDR5 RAM",
                "2x 1.92 TB NVMe SSD",
            ],
            traffic: "unlimited",
            distOptions: ["Ubuntu 24.04", "Debian 12"],
            prices: [
                StandardLocationPrice(location: "FSN1", monthlyNet: 119.00, monthlyGross: 141.61, setupNet: 39.90, setupGross: 47.48),
            ],
            currency: "EUR"
        ),
    ]

    static let transactions: [TransactionSummary] = [
        TransactionSummary(
            id: "B20250601-1234567", date: Date().addingTimeInterval(-3600 * 5),
            status: .inProcess, productName: "EX44", serverNumber: nil
        ),
        TransactionSummary(
            id: "B20250501-7654321", date: Date().addingTimeInterval(-86400 * 30),
            status: .ready, productName: "AX41-NVMe", serverNumber: 123_456
        ),
        TransactionSummary(
            id: "B20250401-1112223", date: Date().addingTimeInterval(-86400 * 90),
            status: .cancelled, productName: "DS 3000", serverNumber: nil
        ),
    ]

    /// Fully loaded view model, ready to render either tab, with no
    /// selections made yet.
    @MainActor
    static func loadedViewModel(tab: OrderTab = .market) -> OrderFlowViewModel {
        let model = OrderFlowViewModel(
            accountID: UUID(),
            accountUsername: "#123456",
            accountLabel: "Primary",
            marketState: .loaded,
            marketListings: marketListings,
            standardState: .loaded,
            standardListings: standardListings,
            sshKeysState: .loaded,
            sshKeys: sshKeys
        )
        model.selectedTab = tab
        return model
    }

    /// A view model with a draft already assembled and armed — useful for
    /// the review screen and every placement-phase result preview.
    @MainActor
    static func reviewViewModel(phase: OrderFlowViewModel.PlacementPhase = .idle) -> OrderFlowViewModel {
        let model = OrderFlowViewModel(
            accountID: UUID(),
            accountUsername: "#123456",
            accountLabel: "Primary",
            marketState: .loaded,
            marketListings: marketListings,
            standardState: .loaded,
            standardListings: standardListings,
            sshKeysState: .loaded,
            sshKeys: sshKeys,
            placementPhase: phase
        )
        model.draft = .market(marketListings[0], sshKeys: [sshKeys[0]])
        model.isArmed = true
        return model
    }
}
