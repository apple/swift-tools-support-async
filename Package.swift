// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "swift-tools-support-async",
    products: [
        .library(
            name: "TSFUtility",
            targets: ["TSFUtility"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.8.0"),
    ],
    targets: [
        .target(
            name: "TSFUtility",
            dependencies: [
                "NIO",
            ]
        ),
    ]
)
