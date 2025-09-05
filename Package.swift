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
        .executable(name: "ip2asn-tools", targets: ["ip2asn-tools"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "SwiftIP2ASN",
            resources: [
                // Place the shipping database at Sources/SwiftIP2ASN/Resources/ip2asn.ultra
                .process("Resources")
            ]
        ),
        .target(
            name: "IP2ASNDataPrep",
            dependencies: ["SwiftIP2ASN"]
        ),
        .executableTarget(
            name: "ip2asn-tools",
            dependencies: ["SwiftIP2ASN", "IP2ASNDataPrep"]
        ),
        .testTarget(
            name: "SwiftIP2ASNTests",
            dependencies: ["SwiftIP2ASN", "IP2ASNDataPrep"]
        ),
    ]
)
