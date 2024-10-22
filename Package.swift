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
        iOSPlatform
    ],
    products: [
        .library(
            name: "SwiftToolsSupportAsync",
            targets: ["TSFFutures", "TSFUtility"]),
        .library(
            name: "SwiftToolsSupportCAS",
            targets: ["TSFCAS", "TSFCASFileTree", "TSFCASUtilities"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.68.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
        .package(url: "https://github.com/apple/swift-tools-support-core.git", "0.5.8" ..< "0.8.0"),
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
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core")
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
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
            ]
        ),

        .target(
            name: "TSFCAS",
            dependencies: [
                "TSFFutures", "TSFUtility", "CBLAKE3",
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
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
