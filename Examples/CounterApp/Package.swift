// swift-tools-version: 6.2
import PackageDescription

// CounterApp — la variante "sin datos" (`ARQUITECTURA-KIT-2026-09-02.md` §1, tabla de
// variantes): View → ViewModel → Logic, sin Service ni Store. `Logic` sigue siendo su
// propio tipo aunque no dependa de nada — es donde vive la regla de negocio, nunca en el
// ViewModel.
let swiftSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault")
]

let package = Package(
    name: "CounterApp",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CounterApp",
            targets: ["CounterApp"]
        )
    ],
    dependencies: [
        // Solo en este monorepo: `path:` al paquete hermano. Un consumidor real usa:
        //   .package(url: "https://github.com/<org>/AppFoundation", from: "1.0.0"),
        .package(path: "../../../AppFoundation")
    ],
    targets: [
        .target(
            name: "CounterApp",
            dependencies: [
                .product(name: "AppFoundation", package: "AppFoundation")
            ],
            path: "Sources/CounterApp",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "CounterAppTests",
            dependencies: [
                "CounterApp",
                .product(name: "AppFoundationTestSupport", package: "AppFoundation")
            ],
            path: "Tests/CounterAppTests",
            swiftSettings: swiftSettings
        )
    ]
)
