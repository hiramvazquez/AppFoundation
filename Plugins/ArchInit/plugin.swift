import Foundation
import PackagePlugin

/// `swift package --allow-writing-to-package-directory archinit`
/// (`AGENTS.md`). Bootstraps a project that's about to
/// adopt AppFoundation's architecture:
///
/// 1. `.archlint.yml` at the package root (commented defaults).
/// 2. `Features/` (where `generate-feature` writes by default).
/// 3. AppFoundation's `AGENTS.md`, copied to the project root.
/// 4. `CLAUDE.md`: creates it (or appends to an existing one) with an `@AGENTS.md` line, so
///    Claude Code picks up the architecture rules automatically.
/// 6. `.swiftlint.yml` from `Templates/swiftlint.yml` (curated SwiftLint config; the plugin
///    itself is added by hand — the two manual steps are printed at the end).
/// 5. `.claude/skills/feature.md` — the `/feature` skill that explains the generator and
///    the lint rules.
///
/// Never overwrites a file that already exists — `archinit` is meant to run once on a
/// fresh project (or safely again on one that already adopted parts of this), never to
/// clobber something a team has since customized.
@main
struct ArchInitPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        // PRD-AF-10: `--multi` is a completely separate code path (its own file set, its
        // own idempotency rules for `Packages/Features/Package.swift`) so it can never
        // change what plain `archinit` does — `Scripts/verify-generator.sh` (PRD-AF-08)
        // stays green untouched.
        var multiExtractor = ArgumentExtractor(arguments)
        if multiExtractor.extractFlag(named: "multi") > 0 {
            try performMultiCommand(context: context, extractor: &multiExtractor)
            return
        }

        let root = context.package.directoryURL
        let fileManager = FileManager.default

        // MARK: 1. .archlint.yml

        try writeIfMissing(
            at: root.appendingPathComponent(".archlint.yml"),
            contents: Self.archLintYML
        )

        // MARK: 2. Features/

        let featuresDir = root.appendingPathComponent("Features")
        if !fileManager.fileExists(atPath: featuresDir.path) {
            try fileManager.createDirectory(at: featuresDir, withIntermediateDirectories: true)
            try Data().write(to: featuresDir.appendingPathComponent(".gitkeep"))
            print("Creado Features/")
        } else {
            print("Ya existe Features/ — sin cambios.")
        }

        // MARK: 3. AGENTS.md

        if let appFoundationDirectory = Self.findAppFoundationDirectory(in: context.package) {
            let source = appFoundationDirectory.appendingPathComponent("AGENTS.md")
            if let data = fileManager.contents(atPath: source.path), let text = String(data: data, encoding: .utf8) {
                try writeIfMissing(at: root.appendingPathComponent("AGENTS.md"), contents: text)
            }

            // MARK: 6. .swiftlint.yml (calidad de código; el plugin de SwiftLint se añade a mano)
            let lintSource = appFoundationDirectory.appendingPathComponent("Templates")
                .appendingPathComponent("swiftlint.yml")
            if let data = fileManager.contents(atPath: lintSource.path), let text = String(data: data, encoding: .utf8)
            {
                try writeIfMissing(at: root.appendingPathComponent(".swiftlint.yml"), contents: text)
            }

            // MARK: 5. .claude/skills/feature.md
            let skillSource = appFoundationDirectory.appendingPathComponent("Templates")
                .appendingPathComponent("feature.skill.md")
            if let data = fileManager.contents(atPath: skillSource.path), let text = String(data: data, encoding: .utf8)
            {
                try writeIfMissing(
                    at: root.appendingPathComponent(".claude").appendingPathComponent("skills")
                        .appendingPathComponent("feature.md"),
                    contents: text
                )
            }
        } else {
            Diagnostics.warning("No se encontró AppFoundation en las dependencias — se omiten AGENTS.md y el skill.")
        }

        // MARK: 4. CLAUDE.md

        let claudeMD = root.appendingPathComponent("CLAUDE.md")
        let agentsLine = "@AGENTS.md"
        if let data = fileManager.contents(atPath: claudeMD.path), let text = String(data: data, encoding: .utf8) {
            if !text.contains(agentsLine) {
                let updated = text.hasSuffix("\n") ? text + "\n\(agentsLine)\n" : text + "\n\n\(agentsLine)\n"
                try updated.write(to: claudeMD, atomically: true, encoding: .utf8)
                print("Actualizado CLAUDE.md (añadida '\(agentsLine)').")
            } else {
                print("CLAUDE.md ya referencia '\(agentsLine)' — sin cambios.")
            }
        } else {
            let content = "# CLAUDE.md\n\n\(agentsLine)\n"
            try content.write(to: claudeMD, atomically: true, encoding: .utf8)
            print("Creado CLAUDE.md con '\(agentsLine)'.")
        }

        print("")
        print("Pasos manuales (calidad de código, ver el artículo CodeQuality de AppFoundation):")
        print("  1. En Package.swift, dependencia:")
        print("     .package(url: \"https://github.com/SimplyDanny/SwiftLintPlugins\", from: \"0.65.0\")")
        print("  2. En el target, junto a ArchitectureLint:")
        print("     .plugin(name: \"SwiftLintBuildToolPlugin\", package: \"SwiftLintPlugins\")")
        print("  3. En CI: brew install swiftlint && swiftlint lint --strict Sources Tests")
        print("")
        print(
            "archinit listo. Siguiente paso: swift package --allow-writing-to-package-directory generate-feature <Nombre> [--api] [--local]"
        )
    }

    private func writeIfMissing(at url: URL, contents: String) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            print("Ya existe \(url.lastPathComponent) — sin cambios.")
            return
        }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        print("Creado \(url.lastPathComponent)")
    }

    private static func findAppFoundationDirectory(in package: Package) -> URL? {
        if package.displayName == "AppFoundation" {
            return package.directoryURL
        }
        for dependency in package.dependencies {
            if let found = findAppFoundationDirectory(in: dependency.package) {
                return found
            }
        }
        return nil
    }

    // MARK: - --multi (PRD-AF-10)

    /// A file `archinit --multi` wants written, relative to `--root`.
    private struct PlannedFile {
        let url: URL
        let contents: String
    }

    /// `swift package --allow-writing-to-package-directory archinit --multi [--root <dir>]
    /// [--name <App>] [--bundle-id <id>] [--capability <Cap>]… [--adapter <Sdk>]…
    /// [--no-xcodegen] [--dry-run]`. Invoked from `Packages/Features` (the minimal
    /// manifest the PRD's «Arranque» section has you create by hand first — the only
    /// manual step: a command plugin only runs on a package that already depends on
    /// AppFoundation).
    ///
    /// Generates the full three-level structure under `--root` (`App/`, `AppTests/`,
    /// `AppUITests/`, `Packages/Platform`, `Packages/Features`, root config) and rewrites
    /// `Packages/Features/Package.swift` with its final, marker-carrying form. Every
    /// OTHER file follows the same `writeIfMissing` policy as plain `archinit` (never
    /// clobbers something already there — prints a suggested diff instead);
    /// `Packages/Features/Package.swift` is the one deliberate exception, rewritten
    /// unconditionally UNTIL it already carries the `archinit:features-begin` marker (at
    /// that point `generate-feature` owns it, and this stops touching it).
    private func performMultiCommand(context: PluginContext, extractor: inout ArgumentExtractor) throws {
        let fileManager = FileManager.default

        let rootOption = extractor.extractOption(named: "root").first
        let nameRaw = extractor.extractOption(named: "name").first ?? "App"
        let bundleIDOption = extractor.extractOption(named: "bundle-id").first
        let capabilityRaw = extractor.extractOption(named: "capability")
        let adapterRaw = extractor.extractOption(named: "adapter")
        let noXcodegen = extractor.extractFlag(named: "no-xcodegen") > 0
        let dryRun = extractor.extractFlag(named: "dry-run") > 0

        let name = ArchInitSupport.pascalCase(nameRaw)
        let bundleID = bundleIDOption ?? "com.example.\(name.lowercased())"

        // Dedup preservando orden: `--capability Camera --capability Camera` es un error
        // de copia y pega, no dos capacidades distintas.
        let capabilities = ArchInitSupport.dedupPascalCase(capabilityRaw)
        let adapters = ArchInitSupport.dedupPascalCase(adapterRaw)
        let hasFirebase = adapters.contains("Firebase")
        let genericAdapters = adapters.filter { $0 != "Firebase" }

        let packageDir = context.package.directoryURL
        let root: URL
        if let rootOption {
            let base = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            root = URL(fileURLWithPath: rootOption, relativeTo: base).standardizedFileURL
        } else {
            // Por defecto, el padre de Packages/ — asume la invocación documentada desde
            // Packages/Features.
            root = packageDir.deletingLastPathComponent().deletingLastPathComponent()
        }

        guard let appFoundationDir = Self.findAppFoundationDirectory(in: context.package) else {
            throw ArchInitMultiError.appFoundationNotFound
        }
        let templatesDir = appFoundationDir.appendingPathComponent("Templates").appendingPathComponent("Multi")

        func loadTemplate(_ fileName: String) throws -> String {
            let url = templatesDir.appendingPathComponent(fileName)
            guard let data = fileManager.contents(atPath: url.path), let text = String(data: data, encoding: .utf8)
            else {
                throw ArchInitMultiError.templateMissing(fileName)
            }
            return text
        }

        func render(
            _ fileName: String,
            substitutions: [String: String] = [:],
            flags: [String: Bool] = [:]
        ) throws -> String {
            TemplateEngine.render(try loadTemplate(fileName), substitutions: substitutions, flags: flags)
        }

        let baseSubstitutions: [String: String] = ["Name": name, "BundleID": bundleID]
        let baseFlags: [String: Bool] = ["hasFirebase": hasFirebase]

        // MARK: Packages/Platform

        var writes: [PlannedFile] = []

        writes.append(
            PlannedFile(
                url: root.appendingPathComponent("Packages/Platform/Sources/Domain/Domain.swift"),
                contents: try render("Domain.swift.txt")
            )
        )
        writes.append(
            PlannedFile(
                url: root.appendingPathComponent("Packages/Platform/Tests/DomainTests/DomainTests.swift"),
                contents: try render("DomainTests.swift.txt")
            )
        )
        for cap in capabilities {
            let subs = ["Cap": cap]
            writes.append(
                PlannedFile(
                    url: root.appendingPathComponent("Packages/Platform/Sources/Domain/\(cap)Providing.swift"),
                    contents: try render("DomainCapabilityProtocol.swift.txt", substitutions: subs)
                )
            )
            writes.append(
                PlannedFile(
                    url: root.appendingPathComponent("Packages/Platform/Sources/\(cap)Kit/\(cap)Kit.swift"),
                    contents: try render("CapKit.swift.txt", substitutions: subs)
                )
            )
        }
        if hasFirebase {
            writes.append(
                PlannedFile(
                    url: root.appendingPathComponent("Packages/Platform/Sources/Domain/AnalyticsTracking.swift"),
                    contents: try render("DomainAnalyticsTracking.swift.txt")
                )
            )
            writes.append(
                PlannedFile(
                    url: root.appendingPathComponent("Packages/Platform/Sources/Domain/CrashReporting.swift"),
                    contents: try render("DomainCrashReporting.swift.txt")
                )
            )
            writes.append(
                PlannedFile(
                    url: root.appendingPathComponent(
                        "Packages/Platform/Sources/FirebaseAdapters/FirebaseAdapters.swift"
                    ),
                    contents: try render("FirebaseAdapters.swift.txt")
                )
            )
        }
        for sdk in genericAdapters {
            let subs = ["Sdk": sdk]
            writes.append(
                PlannedFile(
                    url: root.appendingPathComponent("Packages/Platform/Sources/Domain/\(sdk)Adapting.swift"),
                    contents: try render("GenericAdapterProtocol.swift.txt", substitutions: subs)
                )
            )
            writes.append(
                PlannedFile(
                    url: root.appendingPathComponent("Packages/Platform/Sources/\(sdk)Adapters/\(sdk)Adapters.swift"),
                    contents: try render("GenericAdapter.swift.txt", substitutions: subs)
                )
            )
        }
        writes.append(
            PlannedFile(
                url: root.appendingPathComponent("Packages/Platform/Package.swift"),
                contents: ArchInitSupport.buildPlatformPackageSwift(capabilities: capabilities, adapters: adapters)
            )
        )
        writes.append(
            PlannedFile(url: root.appendingPathComponent("Packages/Platform/.archlint.yml"), contents: Self.archLintYML)
        )

        // MARK: App/, AppTests/, AppUITests/

        writes.append(
            PlannedFile(
                url: root.appendingPathComponent("App/\(name)App.swift"),
                contents: try render("AppApp.swift.txt", substitutions: baseSubstitutions, flags: baseFlags)
            )
        )
        writes.append(
            PlannedFile(
                url: root.appendingPathComponent("App/RootView.swift"),
                contents: try render("RootView.swift.txt", substitutions: baseSubstitutions)
            )
        )
        writes.append(
            PlannedFile(
                url: root.appendingPathComponent("App/AppRoute.swift"),
                contents: try render("AppRoute.swift.txt", substitutions: baseSubstitutions)
            )
        )
        writes.append(
            PlannedFile(
                url: root.appendingPathComponent("App/AppModule.swift"),
                contents: try render(
                    "AppModule.swift.txt",
                    substitutions: baseSubstitutions.merging(
                        [
                            "ModuleImports": ArchInitSupport.moduleImports(
                                capabilities: capabilities,
                                hasFirebase: hasFirebase,
                                genericAdapters: genericAdapters
                            ),
                            "KitRegistrations": ArchInitSupport.kitRegistrations(capabilities: capabilities),
                            "AdapterRegistrations": ArchInitSupport.adapterRegistrations(
                                hasFirebase: hasFirebase,
                                genericAdapters: genericAdapters
                            )
                        ],
                        uniquingKeysWith: { _, new in new }
                    )
                )
            )
        )
        for (relativePath, contents) in ArchInitSupport.assetsXcassets() {
            writes.append(
                PlannedFile(
                    url: root.appendingPathComponent("App/Assets.xcassets").appendingPathComponent(relativePath),
                    contents: contents
                )
            )
        }
        writes.append(
            PlannedFile(
                url: root.appendingPathComponent("AppTests/CompositionRootTests.swift"),
                contents: try render("CompositionRootTests.swift.txt", substitutions: baseSubstitutions)
            )
        )
        writes.append(
            PlannedFile(
                url: root.appendingPathComponent("AppUITests/LaunchTests.swift"),
                contents: try render("LaunchTests.swift.txt")
            )
        )

        // MARK: Root config

        writes.append(
            PlannedFile(
                url: root.appendingPathComponent(".archlint.yml"),
                contents: Self.archLintYML + "\n"
                    + ArchInitSupport.rootModulesYAML(capabilities: capabilities, adapters: adapters)
            )
        )
        writes.append(
            PlannedFile(url: root.appendingPathComponent(".gitignore"), contents: try loadTemplate("gitignore.txt"))
        )

        if let data = fileManager.contents(
            atPath: appFoundationDir.appendingPathComponent("Templates").appendingPathComponent("swiftlint.yml").path
        ), let swiftlintText = String(data: data, encoding: .utf8) {
            writes.append(PlannedFile(url: root.appendingPathComponent(".swiftlint.yml"), contents: swiftlintText))
        }
        if let data = fileManager.contents(atPath: appFoundationDir.appendingPathComponent(".swift-format").path),
            let swiftFormatText = String(data: data, encoding: .utf8)
        {
            writes.append(PlannedFile(url: root.appendingPathComponent(".swift-format"), contents: swiftFormatText))
        }
        if let data = fileManager.contents(atPath: appFoundationDir.appendingPathComponent("AGENTS.md").path),
            let agentsText = String(data: data, encoding: .utf8)
        {
            let full =
                agentsText + ArchInitSupport.modulesSection(name: name, capabilities: capabilities, adapters: adapters)
            writes.append(PlannedFile(url: root.appendingPathComponent("AGENTS.md"), contents: full))
        }
        if let data = fileManager.contents(
            atPath: appFoundationDir.appendingPathComponent("Templates").appendingPathComponent("feature.skill.md").path
        ), let skillText = String(data: data, encoding: .utf8) {
            writes.append(
                PlannedFile(url: root.appendingPathComponent(".claude/skills/feature.md"), contents: skillText)
            )
        }

        if !noXcodegen {
            writes.append(
                PlannedFile(
                    url: root.appendingPathComponent("project.yml"),
                    contents: try render(
                        "project.yml.txt",
                        substitutions: baseSubstitutions.merging(
                            [
                                "PlatformProductDeps": ArchInitSupport.platformProductDeps(
                                    capabilities: capabilities,
                                    adapters: adapters
                                ),
                                "HiddenPackageSchemes": ArchInitSupport.hiddenPackageSchemes(
                                    name: name,
                                    capabilities: capabilities,
                                    adapters: adapters
                                )
                            ],
                            uniquingKeysWith: { _, new in new }
                        )
                    )
                )
            )
            writes.append(
                PlannedFile(
                    url: root.appendingPathComponent(".github/workflows/ci.yml"),
                    contents: try loadTemplate("ci.yml.txt").replacingOccurrences(of: "{{Name}}", with: name)
                )
            )
            writes.append(
                PlannedFile(
                    url: root.appendingPathComponent("Scripts/bootstrap.sh"),
                    contents: try render("bootstrap.sh.txt", substitutions: baseSubstitutions)
                )
            )
        }

        // MARK: Packages/Features (special-cased below: rewritten until it has the marker)

        let featuresPackageURL = root.appendingPathComponent("Packages/Features/Package.swift")
        let featuresArchLintURL = root.appendingPathComponent("Packages/Features/.archlint.yml")
        let featuresMultiMarkerURL = root.appendingPathComponent("Packages/Features/.archinit-multi")
        let claudeMDURL = root.appendingPathComponent("CLAUDE.md")

        if dryRun {
            print("archinit --multi --dry-run (nada se escribe) — raíz: \(root.path)")
            for file in writes {
                print("  \(ArchInitSupport.displayPath(file.url, root: root))")
            }
            print("  \(ArchInitSupport.displayPath(featuresArchLintURL, root: root))")
            print("  \(ArchInitSupport.displayPath(featuresMultiMarkerURL, root: root))")
            print(
                "  \(ArchInitSupport.displayPath(featuresPackageURL, root: root)) (reescrito con la forma final si aún no tiene los markers archinit:*)"
            )
            print("  \(ArchInitSupport.displayPath(claudeMDURL, root: root))")
            return
        }

        for file in writes {
            try writeIfMissingWithDiff(at: file.url, contents: file.contents, root: root)
        }
        try writeIfMissingWithDiff(at: featuresArchLintURL, contents: Self.archLintYML, root: root)
        try writeIfMissingWithDiff(at: featuresMultiMarkerURL, contents: "", root: root)

        if let data = fileManager.contents(atPath: featuresPackageURL.path),
            let existing = String(data: data, encoding: .utf8),
            existing.contains("archinit:features-begin")
        {
            print(
                "Ya existe \(ArchInitSupport.displayPath(featuresPackageURL, root: root)) en modo multi — sin cambios "
                    + "(generate-feature lo edita entre los markers, archinit --multi no vuelve a tocarlo)."
            )
        } else {
            try fileManager.createDirectory(
                at: featuresPackageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try ArchInitSupport.buildFeaturesPackageSwift()
                .write(to: featuresPackageURL, atomically: true, encoding: .utf8)
            print(
                "Reescrito \(ArchInitSupport.displayPath(featuresPackageURL, root: root)) con la forma final (modo multi)."
            )
        }

        // MARK: CLAUDE.md (misma forma que el modo single, copia propia para no tocar ese camino)

        if let data = fileManager.contents(atPath: claudeMDURL.path), let text = String(data: data, encoding: .utf8) {
            if !text.contains("@AGENTS.md") {
                let updated = text.hasSuffix("\n") ? text + "\n@AGENTS.md\n" : text + "\n\n@AGENTS.md\n"
                try updated.write(to: claudeMDURL, atomically: true, encoding: .utf8)
                print("Actualizado \(ArchInitSupport.displayPath(claudeMDURL, root: root)) (añadida '@AGENTS.md').")
            } else {
                print(
                    "\(ArchInitSupport.displayPath(claudeMDURL, root: root)) ya referencia '@AGENTS.md' — sin cambios."
                )
            }
        } else {
            try fileManager.createDirectory(
                at: claudeMDURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try "# CLAUDE.md\n\n@AGENTS.md\n".write(to: claudeMDURL, atomically: true, encoding: .utf8)
            print("Creado \(ArchInitSupport.displayPath(claudeMDURL, root: root)) con '@AGENTS.md'.")
        }

        if !noXcodegen {
            let bootstrapPath = root.appendingPathComponent("Scripts/bootstrap.sh").path
            if fileManager.fileExists(atPath: bootstrapPath) {
                try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bootstrapPath)
            }
        }

        print("")
        print("archinit --multi listo en \(root.path).")
        print("Estructura: App/, AppTests/, AppUITests/, Packages/Platform, Packages/Features.")
        if !capabilities.isEmpty { print("Capacidades: \(capabilities.joined(separator: ", "))") }
        if !adapters.isEmpty { print("Adapters: \(adapters.joined(separator: ", "))") }
        print("")
        print("Siguiente paso:")
        print(
            "  cd Packages/Features && swift package --allow-writing-to-package-directory generate-feature <Nombre> [--api] [--local]"
        )
        if !noXcodegen {
            print("  Scripts/bootstrap.sh   (necesita xcodegen: brew install xcodegen)")
        }
    }

    /// Same `writeIfMissing` policy as plain `archinit`, plus a suggested diff when the
    /// file already exists and its content differs — a simple line-position comparison
    /// (not a true LCS diff), enough to spot drift without pulling in a diff algorithm.
    private func writeIfMissingWithDiff(at url: URL, contents: String, root: URL) throws {
        let fileManager = FileManager.default
        if let data = fileManager.contents(atPath: url.path), let existing = String(data: data, encoding: .utf8) {
            if existing == contents {
                print("Ya existe \(ArchInitSupport.displayPath(url, root: root)) — sin cambios.")
            } else {
                print(
                    "Ya existe \(ArchInitSupport.displayPath(url, root: root)) — difiere del generado, diff sugerido:"
                )
                print(ArchInitSupport.suggestedDiff(existing: existing, proposed: contents))
            }
            return
        }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        print("Creado \(ArchInitSupport.displayPath(url, root: root))")
    }

    private static let archLintYML = """
        # .archlint.yml — configuración de ArchitectureLint.
        # Formato: 'key: value' plano, con listas en bloque ('- item') o inline ('[a, b]').
        # Ver AppFoundation/README.md § Generador y linter para el detalle de cada regla (R1-R12).

        # strict: true exige que cada ViewModel herede de LogicViewModel<any XxxLogicProtocol>
        # en vez de BaseViewModel a pelo.
        strict: false

        # Sufijos que identifican cada capa por nombre de fichero.
        suffixes.viewModel: ViewModel
        suffixes.logic: Logic
        suffixes.service: Service
        suffixes.store: Store
        suffixes.module: Module

        # Reglas desactivadas (por id, p. ej. R11 si @MainActor en una Logic es intencional
        # en este proyecto).
        disabled: []

        # Rutas ignoradas (glob: '*' un segmento, '**' cualquier profundidad). Esta lista
        # REEMPLAZA los defaults de archlint (Tests/**, *Tests.swift, *Mock.swift, *Spy.swift,
        # *Stub.swift): sin este fichero, archlint usa esos defaults. Al margen de lo que
        # pongas aquí, .build/, .swiftpm/, DerivedData/ y .git/ se ignoran SIEMPRE — ahí
        # viven las dependencias descargadas y los productos de build, no tu código.
        ignore:
          - Tests/**
          - "**/Mocks/**"

        """
}

enum ArchInitMultiError: Error, CustomStringConvertible {
    case appFoundationNotFound
    case templateMissing(String)

    var description: String {
        switch self {
        case .appFoundationNotFound:
            return "No se encontró AppFoundation en las dependencias — archinit --multi necesita Templates/Multi."
        case .templateMissing(let name):
            return "Falta la plantilla '\(name)' en AppFoundation/Templates/Multi."
        }
    }
}
