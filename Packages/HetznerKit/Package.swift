// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HetznerKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "HetznerKit", targets: ["HetznerKit"]),
    ],
    targets: [
        .target(
            name: "HetznerKit",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "HetznerKitTests",
            dependencies: ["HetznerKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
