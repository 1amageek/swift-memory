// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "swift-memory",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SwiftMemory", targets: ["SwiftMemory"]),
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
            name: "SwiftMemory",
            dependencies: [
                .product(name: "FDBite", package: "database-framework"),
                .product(name: "Hoot", package: "swift-hoot"),
            ]
        ),
        .testTarget(
            name: "SwiftMemoryTests",
            dependencies: ["SwiftMemory"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
