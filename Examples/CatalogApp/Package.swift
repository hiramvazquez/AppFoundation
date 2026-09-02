// swift-tools-version: 6.2
import PackageDescription

// CatalogApp — la variante "API + local" (`ARQUITECTURA-KIT-2026-09-02.md` §1, tabla de
// variantes): View → ViewModel → Logic → Service + Store, con política cache-then-network
// (§8, M7): `CatalogLogic.cached()` + `.refresh()`.
let swiftSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault")
]

let package = Package(
    name: "CatalogApp",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CatalogApp",
            targets: ["CatalogApp"]
        )
    ],
    dependencies: [
        // Solo en este monorepo: `path:` a los dos paquetes hermanos. Un consumidor real usa:
        //   .package(url: "https://github.com/<org>/AppFoundation", from: "1.0.0"),
        //   .package(url: "https://github.com/<org>/CoreNetworking", from: "1.0.0"),
        .package(path: "../../../AppFoundation"),
        .package(url: "https://github.com/hiramvazquez/CoreNetworking.git", branch: "main")
    ],
    targets: [
        .target(
            name: "CatalogApp",
            dependencies: [
                .product(name: "AppFoundation", package: "AppFoundation"),
                .product(name: "CoreNetworking", package: "CoreNetworking")
            ],
            path: "Sources/CatalogApp",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "CatalogAppTests",
            dependencies: [
                "CatalogApp",
                .product(name: "AppFoundationTestSupport", package: "AppFoundation"),
                .product(name: "CoreNetworkingTestSupport", package: "CoreNetworking")
            ],
            path: "Tests/CatalogAppTests",
            swiftSettings: swiftSettings
        )
    ]
)
