// swift-tools-version:5.5
import PackageDescription

import class Foundation.ProcessInfo

let macOSPlatform: SupportedPlatform
let iOSPlatform: SupportedPlatform
if let deploymentTarget = ProcessInfo.processInfo.environment["SWIFTTSC_MACOS_DEPLOYMENT_TARGET"] {
    macOSPlatform = .macOS(deploymentTarget)
} else {
    macOSPlatform = .macOS(.v10_15)
}
if let deploymentTarget = ProcessInfo.processInfo.environment["SWIFTTSC_IOS_DEPLOYMENT_TARGET"] {
    iOSPlatform = .iOS(deploymentTarget)
} else {
    iOSPlatform = .iOS(.v13)
}

let package = Package(
    name: "swift-tools-support-async",
    platforms: [
        macOSPlatform,
        iOSPlatform,
    ],
    products: [
        .library(
            name: "SwiftToolsSupportAsync",
            targets: ["TSFFutures", "TSFUtility", "TSFAsyncProcess"]),
        .library(
            name: "SwiftToolsSupportCAS",
            targets: ["TSFCAS", "TSFCASFileTree", "TSFCASUtilities"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.0.4"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.4.2"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.68.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.1.1"),
        .package(url: "https://github.com/apple/swift-tools-support-core.git", "0.5.8"..<"0.8.0"),
    ],
    targets: [
        // BLAKE3 hash support
        .target(
            name: "CBLAKE3",
            dependencies: [],
            cSettings: [
                .headerSearchPath("./")
            ]
        ),

        // Async Process vendored library
        .target(
            name: "TSFAsyncProcess",
            dependencies: [
                "TSFProcessSpawnSync",
                .product(name: "Atomics", package: "swift-atomics"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "DequeModule", package: "swift-collections"),
                .product(name: "SystemPackage", package: "swift-system"),
            ],
            path: "Sources/AsyncProcess"
        ),
        .testTarget(
            name: "TSFAsyncProcessTests",
            dependencies: [
                "TSFAsyncProcess",
                .product(name: "Atomics", package: "swift-atomics"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "_NIOFileSystem", package: "swift-nio"),
            ],
            path: "Tests/AsyncProcessTests"
        ),
        .target(
            name: "TSFCProcessSpawnSync",
            path: "Sources/CProcessSpawnSync",
            cSettings: [
                .define("_GNU_SOURCE")
            ]
        ),
        .target(
            name: "TSFProcessSpawnSync",
            dependencies: [
                "TSFCProcessSpawnSync",
                .product(name: "Atomics", package: "swift-atomics"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
            ],
            path: "Sources/ProcessSpawnSync"
        ),

        .target(
            name: "TSFFutures",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
            ]
        ),
        .testTarget(
            name: "TSFFuturesTests",
            dependencies: [
                "TSFFutures"
            ]
        ),
        .target(
            name: "TSFUtility",
            dependencies: [
                "TSFFutures",
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
            ]
        ),

        .target(
            name: "TSFCAS",
            dependencies: [
                "TSFFutures", "TSFUtility", "CBLAKE3",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]
        ),
        .target(
            name: "TSFCASUtilities",
            dependencies: [
                "TSFCAS", "TSFCASFileTree",
            ]
        ),
        .testTarget(
            name: "TSFCASTests",
            dependencies: ["TSFCAS"]
        ),
        .testTarget(
            name: "TSFCASUtilitiesTests",
            dependencies: ["TSFCASUtilities"]
        ),
        .target(
            name: "TSFCASFileTree",
            dependencies: ["TSFCAS"]
        ),
        .testTarget(
            name: "TSFCASFileTreeTests",
            dependencies: ["TSFCASFileTree"]
        ),
    ]
)
