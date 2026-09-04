// swift-tools-version: 6.2
import Foundation
import PackageDescription

// CatalogApp — la variante "API + local" (`ARQUITECTURA-KIT-2026-09-02.md` §1, tabla de
// variantes): View → ViewModel → Logic → Service + Store, con política cache-then-network
// (§8, M7): `CatalogLogic.cached()` + `.refresh()`.
let swiftSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault")
]

// CoreNetworking se resuelve según DÓNDE viva este manifiesto, sin variable de entorno
// ni paso de sustitución al publicar:
//
// - En el monorepo `spm-pro`, `../../../CoreNetworking` es un directorio hermano: se
//   resuelve por `path:` para que un cambio rompedor en el arbol de trabajo lo vea este
//   ejemplo (y el CI) ANTES de publicarse, no después.
// - En el repositorio PUBLICADO de AppFoundation (creado por `git subtree split`, que solo
//   lleva el directorio `AppFoundation/`) ese hermano no existe, y se resuelve por URL.
//
// Un solo `Package.swift` sirve a los dos sitios: sin esto, el `path:` rompía el job
// `example` del CI del repo publicado, y la URL fija dejaba al monorepo probando contra
// una versión ya publicada de CoreNetworking en vez de contra la suya.
let coreNetworkingSibling = "\(Context.packageDirectory)/../../../CoreNetworking"
let coreNetworking: Package.Dependency =
    FileManager.default.fileExists(atPath: coreNetworkingSibling + "/Package.swift")
    ? .package(path: coreNetworkingSibling)
    : .package(url: "https://github.com/hiramvazquez/CoreNetworking.git", from: "1.0.0")

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
        // Solo en este monorepo: `path:` a los dos paquetes hermanos, para que un cambio
        // rompedor en CoreNetworking lo vea este ejemplo (y el CI) ANTES de publicarse, no
        // después. Un consumidor real usa:
        //   .package(url: "https://github.com/hiramvazquez/AppFoundation", from: "1.0.0"),
        //   .package(url: "https://github.com/hiramvazquez/CoreNetworking", from: "1.0.0"),
        // AppFoundation: `../..` es la raíz del paquete en AMBOS sitios (el monorepo y
        // el repo publicado), así que no necesita el tratamiento de arriba.
        .package(path: "../.."),
        coreNetworking
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
