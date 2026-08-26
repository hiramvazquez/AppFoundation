// swift-tools-version: 6.2

import PackageDescription

// Approachable Concurrency (Swift 6.2): el mundo empieza single-threaded en MainActor y la
// concurrencia se introduce a propósito. El modo de lenguaje 6 ya subsume
// DisableOutwardActorInference, GlobalActorIsolatedTypesUsability e InferSendableFromCaptures;
// los dos upcoming de abajo son los que el modo 6 NO subsume todavía.
let swiftSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    // Modo estricto (nivel 0): el compilador es el primer reviewer.
    .treatAllWarnings(as: .error),
    // Excepción puntual: Bundle.appStoreReceiptURL está deprecado en iOS 18 sin reemplazo
    // síncrono (ver AppEnvironment.isTestFlight). La deprecación queda visible como warning,
    // no bloquea el build.
    .treatWarning("DeprecatedDeclaration", as: .warning)
]

let package = Package(
    name: "AppFoundation",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
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
            path: "Sources/AppFoundation",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AppFoundationTests",
            dependencies: ["AppFoundation"],
            path: "Tests/AppFoundationTests",
            swiftSettings: swiftSettings
        )
    ]
)
