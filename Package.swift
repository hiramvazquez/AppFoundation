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

// `archlint` (PRD-AF-08) es una herramienta de línea de comandos, no una app: no necesita
// `defaultIsolation(MainActor)` ni los upcoming features de concurrencia del resto del
// paquete — es puro análisis léxico síncrono. Mismo `-warnings-as-errors` en modo estricto.
var toolSwiftSettings: [SwiftSetting] = []
if modoEstricto {
    toolSwiftSettings.append(.treatAllWarnings(as: .error))
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
        ),
        // PRD-AF-08: el generador (`generate-feature`), el linter — como build-tool
        // plugin (`ArchitectureLint`, se añade a un target) y como command plugin
        // (`ArchLintCommand`, `swift package archlint`, para CI) — y `archinit`.
        // Cada plugin se expone como producto propio para que un consumidor los
        // referencie por `package: "AppFoundation"` sin arrastrar el ejecutable
        // `archlint` como dependencia de su target de producto.
        .plugin(
            name: "ArchitectureLint",
            targets: ["ArchitectureLint"]
        ),
        .plugin(
            name: "ArchLintCommand",
            targets: ["ArchLintCommand"]
        ),
        .plugin(
            name: "GenerateFeature",
            targets: ["GenerateFeature"]
        ),
        .plugin(
            name: "ArchInit",
            targets: ["ArchInit"]
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
        ),

        // MARK: - PRD-AF-08: archlint, generador, plugins

        // El analizador léxico: sin dependencias externas (`ARQUITECTURA-KIT-2026-09-02.md`
        // §4), macOS-only como todo lo que compila y corre en la máquina del desarrollador
        // — nunca en el binario de producción de un consumidor iOS (ver nota en el producto
        // `AppFoundation`, que no depende de este target).
        .executableTarget(
            name: "archlint",
            path: "Sources/archlint",
            swiftSettings: toolSwiftSettings
        ),
        .testTarget(
            name: "ArchLintTests",
            dependencies: ["archlint"],
            path: "Tests/ArchLintTests",
            resources: [
                .copy("Fixtures")
            ],
            swiftSettings: toolSwiftSettings
        ),

        // El motor de plantillas de `GenerateFeature`, como target de biblioteca propio:
        // un plugin no puede depender de un target de biblioteca (SwiftPM lo rechaza:
        // "this dependency is unsupported"), así que `Plugins/GenerateFeature/
        // TemplateEngine.swift` es un symlink A ESTE fichero — se compila DENTRO del
        // target del plugin (sin `import` cruzado) y, a la vez, es exactamente el código
        // que `GenerateFeatureSupportTests` prueba con `@testable import`. Un solo fichero,
        // sin duplicar ni desincronizar.
        .target(
            name: "GenerateFeatureSupport",
            path: "Sources/GenerateFeatureSupport",
            swiftSettings: toolSwiftSettings
        ),
        .testTarget(
            name: "GenerateFeatureSupportTests",
            dependencies: ["GenerateFeatureSupport"],
            path: "Tests/GenerateFeatureSupportTests",
            swiftSettings: toolSwiftSettings
        ),

        // Build-tool plugin: se añade a un target con
        // `plugins: [.plugin(name: "ArchitectureLint", package: "AppFoundation")]`. Invoca
        // el ejecutable `archlint` sobre `target.sourceFiles`; un error hace fallar el build
        // con diagnósticos navegables en Xcode.
        .plugin(
            name: "ArchitectureLint",
            capability: .buildTool(),
            dependencies: ["archlint"],
            path: "Plugins/ArchitectureLint"
        ),

        // Command plugin: `swift package archlint [--path DIR]`, para CI (no requiere
        // integrar el plugin en ningún target).
        .plugin(
            name: "ArchLintCommand",
            capability: .command(
                intent: .custom(
                    verb: "archlint",
                    description:
                        "Analiza el paquete con las reglas de arquitectura View → ViewModel → Logic → Services/Stores."
                )
            ),
            dependencies: ["archlint"],
            path: "Plugins/ArchLintCommand"
        ),

        // Command plugin: `swift package --allow-writing-to-package-directory
        // generate-feature <Nombre> [--api] [--local] [--module] [--analytics] [--no-logic]
        // [--no-tests] [--path Features] [--dry-run]`.
        .plugin(
            name: "GenerateFeature",
            capability: .command(
                intent: .custom(
                    verb: "generate-feature",
                    description:
                        "Genera el cascarón de un feature (View → ViewModel → Logic → Services/Stores) desde las plantillas de AppFoundation."
                ),
                permissions: [
                    .writeToPackageDirectory(
                        reason: "Escribe los ficheros generados del feature bajo Sources/ y Tests/."
                    )
                ]
            ),
            path: "Plugins/GenerateFeature"
        ),

        // Command plugin: `swift package --allow-writing-to-package-directory archinit`.
        .plugin(
            name: "ArchInit",
            capability: .command(
                intent: .custom(
                    verb: "archinit",
                    description:
                        "Inicializa un proyecto consumidor: .archlint.yml, Features/, AGENTS.md y el skill de Claude Code."
                ),
                permissions: [
                    .writeToPackageDirectory(
                        reason:
                            "Crea .archlint.yml, Features/, AGENTS.md y .claude/skills/feature.md en la raíz del proyecto."
                    )
                ]
            ),
            path: "Plugins/ArchInit"
        )
    ]
)
