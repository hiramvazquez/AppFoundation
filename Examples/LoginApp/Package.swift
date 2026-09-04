// swift-tools-version: 6.2
import Foundation
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
        // Solo en este monorepo: `path:` a los dos paquetes hermanos, para que un cambio
        // rompedor en CoreNetworking lo vea este ejemplo (y el CI) ANTES de publicarse,
        // no después. Un consumidor real usa las líneas de abajo en su lugar:
        //   .package(url: "https://github.com/hiramvazquez/AppFoundation", from: "1.0.0"),
        //   .package(url: "https://github.com/hiramvazquez/CoreNetworking", from: "1.0.0"),
        // AppFoundation: `../..` es la raíz del paquete en AMBOS sitios (el monorepo y
        // el repo publicado), así que no necesita el tratamiento de arriba.
        .package(path: "../.."),
        coreNetworking
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
