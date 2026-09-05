// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "swift-memory",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MemoryOntology", targets: ["MemoryOntology"]),
        .library(name: "SwiftMemory", targets: ["SwiftMemory"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/1amageek/database-kit.git",
            from: "26.0831.1",
            traits: ["MultiBase"]
        ),
        .package(
            url: "https://github.com/1amageek/database-framework.git",
            from: "26.0905.0",
            traits: ["SQLite", "VectorIndexes", "GraphIndexes", "MultiBase"]
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
                .product(name: "DatabaseKit", package: "database-kit"),
            ]
        ),
        .target(
            name: "SwiftMemory",
            dependencies: [
                "MemoryOntology",
                .product(name: "DatabaseKit", package: "database-kit"),
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
