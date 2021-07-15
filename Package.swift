// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "swift-tools-support-async",
    products: [
        .library(
            name: "SwiftToolsSupportAsync",
            targets: ["TSFFutures", "TSFUtility"]),
        .library(
            name: "SwiftToolsSupportCAS",
            targets: ["TSFCAS", "TSFCASFileTree", "TSFCASUtilities"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.8.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.8.0"),
        .package(url: "https://github.com/apple/swift-tools-support-core.git", from: "0.2.2"),
    ],
    targets: [
        // BLAKE3 hash support
        .target(
            name: "CBLAKE3",
            dependencies: [],
            cSettings: [
                .headerSearchPath("./"),
            ]
        ),

        .target(
            name: "TSFFutures",
            dependencies: [
                "NIO", "SwiftToolsSupport-auto",
            ]
        ),
        .testTarget(
            name: "TSFFuturesTests",
            dependencies: [
                "TSFFutures",
            ]
        ),
        .target(
            name: "TSFUtility",
            dependencies: [
                "TSFFutures",
            ]
        ),

        .target(
            name: "TSFCAS",
            dependencies: [
                "TSFFutures", "TSFUtility", "CBLAKE3", "SwiftProtobuf",
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
