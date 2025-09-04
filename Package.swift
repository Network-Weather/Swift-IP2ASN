// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftIP2ASN",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(
            name: "SwiftIP2ASN",
            targets: ["SwiftIP2ASN"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-format", from: "600.0.0"),
    ],
    targets: [
        .target(
            name: "SwiftIP2ASN",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("GlobalConcurrency")
            ]),
        .testTarget(
            name: "SwiftIP2ASNTests",
            dependencies: ["SwiftIP2ASN"]
        ),
    ]
)
