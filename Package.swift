// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-memory",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "SwiftMemory",
            targets: ["SwiftMemory"]),
    ],
    dependencies: [
        .package(url: "https://github.com/1amageek/kuzu-swift-extension.git", branch: "main"),
        .package(url: "https://github.com/1amageek/OpenFoundationModels.git", branch: "main")
    ],
    targets: [
        .target(
            name: "SwiftMemory",
            dependencies: [
                .product(name: "KuzuSwiftExtension", package: "kuzu-swift-extension"),
                .product(name: "KuzuSwiftMacros", package: "kuzu-swift-extension"),
                .product(name: "OpenFoundationModels", package: "OpenFoundationModels"),
                .product(name: "OpenFoundationModelsMacros", package: "OpenFoundationModels")
            ]),
        .testTarget(
            name: "SwiftMemoryTests",
            dependencies: ["SwiftMemory"]
        ),
    ]
)
