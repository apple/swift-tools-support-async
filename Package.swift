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
            targets: ["TSFCAS", "TSFCASFileTree"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.8.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.8.0"),
        .package(url: "https://github.com/apple/swift-tools-support-core.git", .branch("master")),
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
        .testTarget(
            name: "TSFCASTests",
            dependencies: ["TSFCAS"]
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
