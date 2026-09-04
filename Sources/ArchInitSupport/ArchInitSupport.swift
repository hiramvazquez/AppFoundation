import Foundation

/// Pure, side-effect-free content builders for `archinit --multi` (PRD-AF-10) — the
/// generated `Package.swift`/`.archlint.yml`/`AGENTS.md` fragments, string manipulation,
/// and naming helpers. `Plugins/ArchInit/plugin.swift` does the I/O (reading templates,
/// deciding what to write, `--dry-run`, idempotency against `Packages/Features/
/// Package.swift`'s markers); everything here just takes strings/arrays and returns a
/// string, which is what makes it unit-testable — `ArchitectureLintTests`
/// (`PackagePlugin`'s `PluginContext` can't be constructed outside a real plugin
/// invocation, which is why `plugin.swift` itself has no direct unit tests, only the
/// shell-level integration test documented in the PRD-AF-10 report).
///
/// `Plugins/ArchInit/ArchInitSupport.swift` is a symlink to THIS file (same trick as
/// `GenerateFeatureSupport`/`TemplateEngine.swift`): a plugin target can't depend on a
/// library target, so the same source compiles directly into the plugin's module — no
/// `import` needed there — and is exactly what `ArchInitSupportTests` exercises with
/// `@testable import`.
public enum ArchInitSupport {
    // MARK: - Naming

    public static func pascalCase(_ raw: String) -> String {
        guard let first = raw.first else { return raw }
        return String(first).uppercased() + raw.dropFirst()
    }

    /// Dedup preservando orden: `--capability Camera --capability Camera` es un error de
    /// copia y pega, no dos capacidades distintas.
    public static func dedupPascalCase(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in raw {
            let cased = pascalCase(value)
            if !seen.contains(cased) {
                seen.insert(cased)
                result.append(cased)
            }
        }
        return result
    }

    public static func displayPath(_ url: URL, root: URL) -> String {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return url.path.hasPrefix(rootPath) ? String(url.path.dropFirst(rootPath.count)) : url.path
    }

    // MARK: - Diffing

    /// Same `writeIfMissing` policy as plain `archinit`, plus a suggested diff when the
    /// file already exists and its content differs — a simple line-position comparison
    /// (not a true LCS diff), enough to spot drift without pulling in a diff algorithm.
    public static func suggestedDiff(existing: String, proposed: String) -> String {
        let existingLines = existing.components(separatedBy: "\n")
        let proposedLines = proposed.components(separatedBy: "\n")
        var output: [String] = []
        for index in 0..<max(existingLines.count, proposedLines.count) {
            let oldLine = index < existingLines.count ? existingLines[index] : nil
            let newLine = index < proposedLines.count ? proposedLines[index] : nil
            if oldLine == newLine { continue }
            if let oldLine { output.append("  - \(oldLine)") }
            if let newLine { output.append("  + \(newLine)") }
        }
        return output.isEmpty
            ? "  (sin diferencias visibles — revisa saltos de línea/codificación)" : output.joined(separator: "\n")
    }

    // MARK: - App/AppModule.swift substitutions

    /// `import Platform` doesn't exist — `Platform` is the PACKAGE (manifest) name, not a
    /// module: Swift imports the library PRODUCTS it declares (`Domain`, `CameraKit`,
    /// `FirebaseAdapters`…), one per line, only the ones this file actually references.
    public static func moduleImports(capabilities: [String], hasFirebase: Bool, genericAdapters: [String]) -> String {
        var modules = ["Domain"]
        modules += capabilities.map { "\($0)Kit" }
        if hasFirebase { modules.append("FirebaseAdapters") }
        modules += genericAdapters.map { "\($0)Adapters" }
        return modules.map { "import \($0)" }.joined(separator: "\n")
    }

    public static func kitRegistrations(capabilities: [String]) -> String {
        guard !capabilities.isEmpty else { return "" }
        var lines = ["", "        // MARK: Kits"]
        for cap in capabilities {
            lines.append("        container.register(\(cap)Providing.self) { _ in \(cap)KitProvider() }")
        }
        return lines.joined(separator: "\n")
    }

    public static func adapterRegistrations(hasFirebase: Bool, genericAdapters: [String]) -> String {
        guard hasFirebase || !genericAdapters.isEmpty else { return "" }
        var lines = ["", "        // MARK: Adapters"]
        if hasFirebase {
            lines.append("        container.register(AnalyticsTracking.self) { _ in FirebaseAnalyticsTracker() }")
            lines.append("        container.register(CrashReporting.self) { _ in FirebaseCrashReporter() }")
        }
        for sdk in genericAdapters {
            lines.append("        container.register(\(sdk)Adapting.self) { _ in \(sdk)AdapterStub() }")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - project.yml substitutions

    public static func platformProductDeps(capabilities: [String], adapters: [String]) -> String {
        var lines: [String] = []
        for cap in capabilities {
            lines.append("      - package: Platform")
            lines.append("        product: \(cap)Kit")
        }
        for sdk in adapters {
            lines.append("      - package: Platform")
            lines.append("        product: \(sdk)Adapters")
        }
        guard !lines.isEmpty else { return "" }
        return lines.joined(separator: "\n") + "\n"
    }

    /// `isShown: false` for every Platform product's Xcode-autogenerated scheme — without
    /// this, Xcode clutters the scheme picker with one entry per local-package product the
    /// first time it opens the generated project.
    public static func hiddenPackageSchemes(name: String, capabilities: [String], adapters: [String]) -> String {
        var products = ["Domain"]
        products += capabilities.map { "\($0)Kit" }
        if adapters.contains("Firebase") { products.append("FirebaseAdapters") }
        products += adapters.filter { $0 != "Firebase" }.map { "\($0)Adapters" }

        var lines: [String] = []
        for product in products {
            lines.append("  \(product):")
            lines.append("    build:")
            lines.append("      targets:")
            lines.append("        \(name): [build]")
            lines.append("    management:")
            lines.append("      isShown: false")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Root .archlint.yml (`modules:` section, R13)

    public static func rootModulesYAML(capabilities: [String], adapters: [String]) -> String {
        var lines: [String] = ["modules:", "  Domain:", "    allowedImports: [Foundation]"]
        for cap in capabilities {
            lines.append("  \(cap)Kit:")
            lines.append("    allowedImports: [Foundation, Domain]")
        }
        if adapters.contains("Firebase") {
            lines.append("  FirebaseAdapters:")
            lines.append("    allowedImports: [Foundation, Domain, Firebase*]")
        }
        for sdk in adapters where sdk != "Firebase" {
            lines.append("  \(sdk)Adapters:")
            lines.append("    allowedImports: [Foundation, Domain, \(sdk)*]")
        }
        lines.append("  \"*Feature\":")
        lines.append("    allowedImports: [Foundation, SwiftUI, Observation, AppFoundation, CoreNetworking, Domain]")
        lines.append("    forbiddenImports: [\"*Feature\", \"Firebase*\", \"*Kit\", \"*Adapters\"]")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - AGENTS.md § Módulos de este proyecto

    public static func modulesSection(name: String, capabilities: [String], adapters: [String]) -> String {
        var lines: [String] = [
            "",
            "## Módulos de este proyecto",
            "",
            "Generado por `archinit --multi` (PRD-AF-10). Tabla real de dependencias permitidas —",
            "`.archlint.yml` (raíz, sección `modules:`) la hace cumplir (R13); una fila nueva se",
            "añade a mano cada vez que generas un feature o vuelves a correr `archinit --multi`",
            "con más `--capability`/`--adapter`.",
            "",
            "| Módulo | Puede importar | Nunca importa |",
            "|---|---|---|",
            "| Domain | Foundation | nada más |"
        ]
        for cap in capabilities {
            lines.append("| `\(cap)Kit` | Domain + frameworks del sistema | features, adapters, otro Kit |")
        }
        for sdk in adapters {
            lines.append("| `\(sdk)Adapters` | Domain + el SDK de \(sdk) | features |")
        }
        lines.append(
            "| `<Nombre>Feature` | AppFoundation, CoreNetworking, Domain | otra feature, cualquier SDK, cualquier Kit |"
        )
        lines.append("| \(name) (App) | todo | lógica de negocio |")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    // MARK: - App/Assets.xcassets (minimal, xcodegen-compatible)

    public static func assetsXcassets() -> [(String, String)] {
        [
            (
                "Contents.json",
                "{\n  \"info\": {\n    \"author\": \"xcode\",\n    \"version\": 1\n  }\n}\n"
            ),
            (
                "AppIcon.appiconset/Contents.json",
                "{\n  \"images\": [\n    {\n      \"idiom\": \"universal\",\n      \"platform\": \"ios\",\n"
                    + "      \"size\": \"1024x1024\"\n    }\n  ],\n  \"info\": {\n    \"author\": \"xcode\",\n"
                    + "    \"version\": 1\n  }\n}\n"
            ),
            (
                "AccentColor.colorset/Contents.json",
                "{\n  \"colors\": [\n    {\n      \"idiom\": \"universal\"\n    }\n  ],\n  \"info\": {\n"
                    + "    \"author\": \"xcode\",\n    \"version\": 1\n  }\n}\n"
            )
        ]
    }

    // MARK: - Packages/Platform/Package.swift and Packages/Features/Package.swift

    public static func targetBlock(
        kind: String,
        name: String,
        dependencies: [String],
        path: String,
        withArchLint: Bool
    ) -> [String] {
        var lines: [String] = []
        lines.append("        .\(kind)(")
        lines.append("            name: \"\(name)\",")
        if dependencies.count == 1 {
            lines.append("            dependencies: [\(dependencies[0])],")
        } else if dependencies.count > 1 {
            lines.append("            dependencies: [")
            for dep in dependencies {
                lines.append("                \(dep),")
            }
            lines.append("            ],")
        }
        lines.append("            path: \"\(path)\",")
        if withArchLint {
            lines.append("            swiftSettings: swiftSettings,")
            lines.append("            plugins: [.plugin(name: \"ArchitectureLint\", package: \"AppFoundation\")]")
        } else {
            lines.append("            swiftSettings: swiftSettings")
        }
        lines.append("        ),")
        return lines
    }

    /// The generated `Packages/Platform/Package.swift`: `Domain` (+`DomainTests`), one
    /// `<Cap>Kit` per `--capability`, `FirebaseAdapters` (if `--adapter Firebase`), and
    /// one `<Sdk>Adapters` per other `--adapter`. Fully determined by the given
    /// capabilities/adapters — unlike `Packages/Features/Package.swift`, it carries no
    /// `archinit:*` markers because nothing ever edits it again after this.
    public static func buildPlatformPackageSwift(capabilities: [String], adapters: [String]) -> String {
        let hasFirebase = adapters.contains("Firebase")
        let genericAdapters = adapters.filter { $0 != "Firebase" }

        var products: [String] = ["        .library(name: \"Domain\", targets: [\"Domain\"]),"]
        for cap in capabilities {
            products.append("        .library(name: \"\(cap)Kit\", targets: [\"\(cap)Kit\"]),")
        }
        if hasFirebase {
            products.append("        .library(name: \"FirebaseAdapters\", targets: [\"FirebaseAdapters\"]),")
        }
        for sdk in genericAdapters {
            products.append("        .library(name: \"\(sdk)Adapters\", targets: [\"\(sdk)Adapters\"]),")
        }

        var dependencies: [String] = [
            "        .package(url: \"https://github.com/hiramvazquez/AppFoundation.git\", from: \"1.2.0\"),"
        ]
        if hasFirebase {
            dependencies.append(
                "        // R14: por tag, nunca por rama — ajusta al tag estable más reciente al generar."
            )
            dependencies.append(
                "        .package(url: \"https://github.com/firebase/firebase-ios-sdk\", from: \"11.0.0\"),"
            )
        }

        var targets: [String] = targetBlock(
            kind: "target",
            name: "Domain",
            dependencies: [],
            path: "Sources/Domain",
            withArchLint: true
        )
        targets += targetBlock(
            kind: "testTarget",
            name: "DomainTests",
            dependencies: ["\"Domain\""],
            path: "Tests/DomainTests",
            withArchLint: false
        )
        for cap in capabilities {
            targets += targetBlock(
                kind: "target",
                name: "\(cap)Kit",
                dependencies: ["\"Domain\""],
                path: "Sources/\(cap)Kit",
                withArchLint: true
            )
        }
        if hasFirebase {
            targets += targetBlock(
                kind: "target",
                name: "FirebaseAdapters",
                dependencies: [
                    "\"Domain\"",
                    ".product(name: \"FirebaseAnalytics\", package: \"firebase-ios-sdk\")",
                    ".product(name: \"FirebaseCrashlytics\", package: \"firebase-ios-sdk\")"
                ],
                path: "Sources/FirebaseAdapters",
                withArchLint: true
            )
        }
        for sdk in genericAdapters {
            targets += targetBlock(
                kind: "target",
                name: "\(sdk)Adapters",
                dependencies: ["\"Domain\""],
                path: "Sources/\(sdk)Adapters",
                withArchLint: true
            )
        }

        var lines: [String] = [
            "// swift-tools-version: 6.2",
            "import PackageDescription",
            "",
            "// Generado por `archinit --multi` (PRD-AF-10). Domain: modelos/protocolos compartidos,",
            "// solo Foundation. Un <Cap>Kit por --capability, un <Sdk>Adapters por --adapter — cada",
            "// uno implementa un protocolo de Domain; `.archlint.yml` (raíz, R13) impide que un",
            "// Kit/Adapter importe otro, o que una feature importe cualquiera de los dos.",
            "let swiftSettings: [SwiftSetting] = [",
            "    .defaultIsolation(MainActor.self),",
            "    .enableUpcomingFeature(\"InferIsolatedConformances\"),",
            "    .enableUpcomingFeature(\"NonisolatedNonsendingByDefault\")",
            "]",
            "",
            "let package = Package(",
            "    name: \"Platform\",",
            "    platforms: [",
            "        .iOS(.v17),",
            "        .macOS(.v14)",
            "    ],",
            "    products: ["
        ]
        lines += products
        lines.append("    ],")
        lines.append("    dependencies: [")
        lines += dependencies
        lines.append("    ],")
        lines.append("    targets: [")
        lines += targets
        lines.append("    ]")
        lines.append(")")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// The generated `Packages/Features/Package.swift` — its FINAL form, with the
    /// `archinit:features-begin`/`archinit:features-end` markers (inside `targets:`) and
    /// `archinit:products-begin`/`archinit:products-end` markers (inside `products:`) that
    /// `generate-feature` (modo multi) edits between. `plugin.swift` writes this
    /// unconditionally UNTIL the file on disk already contains `archinit:features-begin`
    /// (at that point `generate-feature` owns it).
    public static func buildFeaturesPackageSwift() -> String {
        let lines: [String] = [
            "// swift-tools-version: 6.2",
            "import PackageDescription",
            "",
            "// Manifiesto reescrito por `archinit --multi` (PRD-AF-10) con su forma final — empezó",
            "// como el manifiesto mínimo de la sección «Arranque» de PRD-AF-10.md (solo dependía de",
            "// AppFoundation). `generate-feature` (modo multi) es la ÚNICA herramienta que edita esto",
            "// después, y solo entre los markers `archinit:*` de abajo — nunca a mano.",
            "let swiftSettings: [SwiftSetting] = [",
            "    .defaultIsolation(MainActor.self),",
            "    .enableUpcomingFeature(\"InferIsolatedConformances\"),",
            "    .enableUpcomingFeature(\"NonisolatedNonsendingByDefault\")",
            "]",
            "",
            "let package = Package(",
            "    name: \"Features\",",
            "    platforms: [",
            "        .iOS(.v17),",
            "        .macOS(.v14)",
            "    ],",
            "    products: [",
            "        // archinit:products-begin",
            "        // archinit:products-end",
            "    ],",
            "    dependencies: [",
            "        .package(url: \"https://github.com/hiramvazquez/AppFoundation.git\", from: \"1.2.0\"),",
            "        .package(url: \"https://github.com/hiramvazquez/CoreNetworking.git\", from: \"1.0.0\"),",
            "        .package(path: \"../Platform\")",
            "    ],",
            "    targets: [",
            "        // archinit:features-begin",
            "        // archinit:features-end",
            "    ]",
            ")",
            ""
        ]
        return lines.joined(separator: "\n")
    }
}
