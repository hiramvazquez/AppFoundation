// swift-tools-version: 6.2
import PackageDescription

// NotesApp — la variante "solo local" (`ARQUITECTURA-KIT-2026-09-02.md` §1, tabla de
// variantes): View → ViewModel → Logic → Store, sin API. SwiftData de verdad
// (`@Model`/`ModelContainer`), no una simulación — la única concesión en tests es un
// `ModelContainer` en memoria (`isStoredInMemoryOnly: true`), nunca un mock del framework.
let swiftSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault")
]

let package = Package(
    name: "NotesApp",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "NotesApp",
            targets: ["NotesApp"]
        )
    ],
    dependencies: [
        // Solo en este monorepo: `path:` al paquete hermano. Un consumidor real usa:
        //   .package(url: "https://github.com/<org>/AppFoundation", from: "1.0.0"),
        .package(path: "../../../AppFoundation")
    ],
    targets: [
        .target(
            name: "NotesApp",
            dependencies: [
                .product(name: "AppFoundation", package: "AppFoundation")
            ],
            path: "Sources/NotesApp",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "NotesAppTests",
            dependencies: [
                "NotesApp",
                .product(name: "AppFoundationTestSupport", package: "AppFoundation")
            ],
            path: "Tests/NotesAppTests",
            swiftSettings: swiftSettings
        )
    ]
)
