// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AppFoundation",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "AppFoundation",
            targets: ["AppFoundation"]
        )
    ],
    targets: [
        .target(
            name: "AppFoundation",
            path: "Sources/AppFoundation"
        ),
        .testTarget(
            name: "AppFoundationTests",
            dependencies: ["AppFoundation"],
            path: "Tests/AppFoundationTests"
        )
    ]
)
