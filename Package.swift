// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Memory",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Memory", targets: ["Memory"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/1amageek/database-kit.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/1amageek/database-framework.git",
            branch: "main",
            traits: ["FDBite"]
        ),
        .package(
            url: "https://github.com/hoot-format/swift-hoot.git",
            from: "0.1.0"
        ),
    ],
    targets: [
        .target(
            name: "Memory",
            dependencies: [
                .product(name: "FDBite", package: "database-framework"),
                .product(name: "Hoot", package: "swift-hoot"),
            ]
        ),
        .testTarget(
            name: "MemoryTests",
            dependencies: ["Memory"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
