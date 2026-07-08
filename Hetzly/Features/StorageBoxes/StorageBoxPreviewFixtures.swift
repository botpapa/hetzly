import Foundation
import HetznerKit

/// Preview-only mock data for the Storage Boxes feature. No network access —
/// every preview in this directory renders from these fixtures. Matches the
/// real `HetznerKit.StorageBoxAPI` model shapes (see
/// `Packages/HetznerKit/Sources/HetznerKit/StorageBoxAPI/`).
enum StorageBoxPreviewFixtures {
    static let location = Location(
        id: 1,
        name: "fsn1",
        description: "Falkenstein DC Park 1",
        country: "DE",
        city: "Falkenstein",
        latitude: 50.47612,
        longitude: 12.370071,
        networkZone: "eu-central"
    )

    static let storageBoxType = StorageBoxType(
        id: 1,
        name: "BX11",
        description: "BX11",
        size: 1_099_511_627_776, // 1 TB
        snapshotLimit: 10,
        automaticSnapshotLimit: 10,
        subaccountsLimit: 200,
        prices: [],
        deprecation: nil
    )

    static let accessSettings = StorageBoxAccessSettings(
        reachableExternally: true,
        sambaEnabled: false,
        sshEnabled: true,
        webdavEnabled: true,
        zfsEnabled: false
    )

    static let stats = StorageBoxStats(
        size: 456_708_198_400,
        sizeData: 400_708_198_400,
        sizeSnapshots: 56_000_000_000
    )

    static let box = StorageBox(
        id: 12345,
        username: "u123456",
        status: .active,
        name: "prod-backups",
        storageBoxType: storageBoxType,
        location: location,
        accessSettings: accessSettings,
        server: "u123456.your-storagebox.de",
        system: "FSN1-BX136",
        stats: stats,
        labels: [:],
        protection: StorageBoxProtection(delete: false),
        snapshotPlan: nil,
        created: Date(timeIntervalSinceNow: -86_400 * 200)
    )

    static let initializingBox = StorageBox(
        id: 12346,
        username: nil,
        status: .initializing,
        name: "archive",
        storageBoxType: storageBoxType,
        location: location,
        accessSettings: accessSettings,
        server: nil,
        system: nil,
        stats: StorageBoxStats(size: 0, sizeData: 0, sizeSnapshots: 0),
        labels: [:],
        protection: StorageBoxProtection(delete: false),
        snapshotPlan: nil,
        created: Date(timeIntervalSinceNow: -3_600)
    )

    static let snapshots: [StorageBoxSnapshot] = [
        StorageBoxSnapshot(
            id: 1,
            name: "2026-07-08T02-00",
            description: "Nightly backup",
            stats: StorageBoxSnapshotStats(size: 12_400_000_000, sizeFilesystem: 40_000_000_000),
            isAutomatic: true,
            labels: [:],
            created: Date(timeIntervalSinceNow: -86_400),
            storageBoxID: box.id
        ),
        StorageBoxSnapshot(
            id: 2,
            name: "before-migration",
            description: "Manual, before DB migration",
            stats: StorageBoxSnapshotStats(size: 8_100_000_000, sizeFilesystem: 39_500_000_000),
            isAutomatic: false,
            labels: [:],
            created: Date(timeIntervalSinceNow: -86_400 * 5),
            storageBoxID: box.id
        ),
    ]

    static let subaccounts: [StorageBoxSubaccount] = [
        StorageBoxSubaccount(
            id: 1,
            name: "App 1 backups",
            username: "u123456-sub1",
            homeDirectory: "backups/app1",
            server: "u123456.your-storagebox.de",
            accessSettings: StorageBoxSubaccountAccessSettings(
                reachableExternally: true, readonly: false, sambaEnabled: false, sshEnabled: true, webdavEnabled: false
            ),
            description: "App 1 nightly dumps",
            labels: [:],
            created: Date(timeIntervalSinceNow: -86_400 * 30),
            storageBoxID: box.id
        ),
    ]
}
