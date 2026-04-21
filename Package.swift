// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "swift-memory",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MemoryOntology", targets: ["MemoryOntology"]),
        .library(name: "SwiftMemory", targets: ["SwiftMemory"]),
    ],
    dependencies: [
        .package(url: "https://github.com/1amageek/database-kit.git", from: "26.0418.0"),
        .package(
            url: "https://github.com/1amageek/database-framework.git",
            from: "26.0421.3",
            traits: ["SQLite"]
        ),
        .package(
            url: "https://github.com/hoot-format/swift-hoot.git",
            from: "0.1.0"
        ),
    ],
    targets: [
        .target(
            name: "MemoryOntology",
            dependencies: [
                .product(name: "Database", package: "database-framework"),
            ]
        ),
        .target(
            name: "SwiftMemory",
            dependencies: [
                "MemoryOntology",
                .product(name: "Core", package: "database-kit"),
                .product(name: "Vector", package: "database-kit"),
                .product(name: "Database", package: "database-framework"),
                .product(name: "Hoot", package: "swift-hoot"),
            ]
        ),
        .testTarget(
            name: "SwiftMemoryTests",
            dependencies: ["SwiftMemory", "MemoryOntology"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
