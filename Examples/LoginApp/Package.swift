// swift-tools-version: 6.2
import PackageDescription

// LoginApp — la variante "solo API" (`ARQUITECTURA-KIT-2026-09-02.md` §1, tabla de
// variantes): View → ViewModel → Logic → Service, sin persistencia local. Sustituye a
// `Examples/IntegrationExample` (`git mv`) — sigue siendo la prueba de que
// AppFoundation y CoreNetworking se adoptan JUNTOS sin fricción, ahora con la
// arquitectura completa de capas en vez de un único `BaseViewModel` hablando con
// `APIServiceProtocol` directamente.
//
// `defaultIsolation(MainActor)`, igual que los dos paquetes que consume: es el modo en el
// que una app SwiftUI real construiría este mismo código.
let swiftSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault")
]

let package = Package(
    name: "LoginApp",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "LoginApp",
            targets: ["LoginApp"]
        )
    ],
    dependencies: [
        // Solo en este monorepo: `path:` a los dos paquetes hermanos. Un consumidor real
        // usa la línea de abajo en su lugar:
        //   .package(url: "https://github.com/<org>/AppFoundation", from: "1.0.0"),
        //   .package(url: "https://github.com/<org>/CoreNetworking", from: "1.0.0"),
        .package(path: "../../../AppFoundation"),
        .package(path: "../../../CoreNetworking")
    ],
    targets: [
        .target(
            name: "LoginApp",
            dependencies: [
                .product(name: "AppFoundation", package: "AppFoundation"),
                .product(name: "CoreNetworking", package: "CoreNetworking"),
                // Previews only (`LoginPreview`, guarded by `#if DEBUG` at the call site)
                // — see `CoreNetworkingTestSupport`'s own Package.swift ("test targets and
                // previews"). SwiftPM's target-dependency conditions don't support a
                // build-configuration case, so this links into every configuration of
                // THIS example target; a real app keeps its own preview target instead.
                .product(name: "CoreNetworkingTestSupport", package: "CoreNetworking")
            ],
            path: "Sources/LoginApp",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "LoginAppTests",
            dependencies: [
                "LoginApp",
                .product(name: "AppFoundationTestSupport", package: "AppFoundation"),
                .product(name: "CoreNetworkingTestSupport", package: "CoreNetworking")
            ],
            path: "Tests/LoginAppTests",
            swiftSettings: swiftSettings
        )
    ]
)
