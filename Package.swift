// swift-tools-version: 6.2

import PackageDescription

// Approachable Concurrency (Swift 6.2): el mundo empieza single-threaded en MainActor y la
// concurrencia se introduce a propósito. El modo de lenguaje 6 ya subsume
// DisableOutwardActorInference, GlobalActorIsolatedTypesUsability e InferSendableFromCaptures;
// los dos upcoming de abajo son los que el modo 6 NO subsume todavía.
// El rigor es una propiedad de COMO SE DESARROLLA el paquete, no del artefacto que
// se publica. Xcode compila las dependencias remotas con `-suppress-warnings` (los
// warnings de una libreria de terceros no son accionables para quien la consume), y
// eso choca de frente con `-warnings-as-errors`:
//
//     error: Conflicting options '-warnings-as-errors' and '-suppress-warnings'
//
// El build del consumidor no fallaba en local solo porque una ruta local se trata
// como codigo propio. Al publicar por URL, el mismo manifiesto rompio la app que lo
// consume — un paquete no debe imponer su nivel 0 a terceros.
//
// Por eso el modo estricto se activa por entorno: aqui dentro (y en el CI del propio
// paquete) esta encendido; para quien lo consume, ausente.
let modoEstricto = Context.environment["SWIFT_STRICT_WARNINGS"] != nil

var swiftSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault")
]

if modoEstricto {
    // Modo estricto (nivel 0): el compilador es el primer reviewer.
    swiftSettings.append(.treatAllWarnings(as: .error))
    // Excepción puntual: Bundle.appStoreReceiptURL está deprecado en iOS 18 sin reemplazo
    // síncrono (ver AppEnvironment.isTestFlight). La deprecación queda visible como warning,
    // no bloquea el build.
    swiftSettings.append(.treatWarning("DeprecatedDeclaration", as: .warning))
}

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
        ),
        // Mocks y helpers de test (`InMemoryStore`, `ManualClock`, `SpyRecorder`): producto
        // SEPARADO, como `CoreNetworkingTestSupport` en CoreNetworking, para que jamás
        // viajen en el binario de producción. Solo lo enlazan test targets y previews —
        // NUNCA aparece como dependencia del producto `AppFoundation` (PRD-AF-07).
        .library(
            name: "AppFoundationTestSupport",
            targets: ["AppFoundationTestSupport"]
        )
    ],
    targets: [
        .target(
            name: "AppFoundation",
            path: "Sources/AppFoundation",
            resources: [
                .process("Resources")
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "AppFoundationTestSupport",
            path: "Sources/AppFoundationTestSupport",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AppFoundationTests",
            dependencies: ["AppFoundation", "AppFoundationTestSupport"],
            path: "Tests/AppFoundationTests",
            swiftSettings: swiftSettings
        )
    ]
)
