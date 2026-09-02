import Foundation
import PackagePlugin

// `TemplateEngine` is not imported from a dependency: `TemplateEngine.swift` in this
// directory is a symlink to `Sources/GenerateFeatureSupport/TemplateEngine.swift` (see
// `Package.swift`) — plugin targets cannot depend on library targets, so the same file
// compiles directly into both this plugin's module and the tested `GenerateFeatureSupport`
// library, instead of two copies that could drift apart.

/// `swift package --allow-writing-to-package-directory generate-feature <Nombre> [--api]
/// [--local] [--module] [--analytics] [--no-logic] [--no-tests] [--path Features]
/// [--dry-run] [--target NAME] [--route AppRoute.xxx]`
/// (`ARQUITECTURA-KIT-2026-09-02.md` §3, PRD-AF-08).
///
/// Genera el cascarón completo View → ViewModel → Logic → Services/Stores de una feature
/// desde las plantillas de texto en `AppFoundation/Templates/` — nunca desde código Swift
/// embebido, para que sigan siendo legibles (y editables) por un humano o un agente que
/// prefiera copiar a mano.
@main
struct GenerateFeaturePlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        var extractor = ArgumentExtractor(arguments)
        let api = extractor.extractFlag(named: "api") > 0
        let local = extractor.extractFlag(named: "local") > 0
        let module = extractor.extractFlag(named: "module") > 0
        let analytics = extractor.extractFlag(named: "analytics") > 0
        let noLogic = extractor.extractFlag(named: "no-logic") > 0
        let noTests = extractor.extractFlag(named: "no-tests") > 0
        let dryRun = extractor.extractFlag(named: "dry-run") > 0
        let pathOption = extractor.extractOption(named: "path").first ?? "Features"
        let targetOption = extractor.extractOption(named: "target").first
        let routeOption = extractor.extractOption(named: "route").first
        let remaining = extractor.remainingArguments

        guard let rawName = remaining.first, !rawName.isEmpty else {
            throw GenerateFeatureError.missingFeatureName
        }
        let feature = Self.pascalCase(rawName)
        let featureLower = Self.camelCase(feature)

        guard let templatesDirectory = Self.findTemplatesDirectory(in: context.package) else {
            throw GenerateFeatureError.templatesNotFound
        }

        guard let target = Self.selectTarget(context.package, named: targetOption) else {
            throw GenerateFeatureError.noTarget
        }
        guard let testTarget = Self.testTarget(for: target, in: context.package) else {
            throw GenerateFeatureError.noTestTarget(target.name)
        }

        let both = api && local
        let none = !api && !local
        let flags: [String: Bool] = [
            "api": api,
            "local": local,
            "both": both,
            "none": none,
            "module": module,
            "analytics": analytics
        ]
        let substitutions: [String: String] = [
            "Feature": feature,
            "feature": featureLower,
            "Module": target.moduleName
        ]

        let engine = TemplateEngine.self
        func render(_ templateName: String) throws -> String {
            let url = templatesDirectory.appendingPathComponent(templateName)
            guard let data = FileManager.default.contents(atPath: url.path),
                let text = String(data: data, encoding: .utf8)
            else {
                throw GenerateFeatureError.templateMissing(templateName)
            }
            return engine.render(text, substitutions: substitutions, flags: flags)
        }

        // MARK: - Destination layout

        // `--module` (M8): las dos mitades viven en subcarpetas `<Feature>Core`/`<Feature>UI`
        // dentro del mismo target — el generador NUNCA edita Package.swift (mismo principio
        // honesto que "no toca el .xcodeproj"): imprime el snippet para promoverlas a dos
        // targets reales si el proyecto los quiere de verdad separados por el compilador.
        let featureSourceDir = target.directoryURL.appendingPathComponent(pathOption).appendingPathComponent(feature)
        let coreDir = module ? featureSourceDir.appendingPathComponent("\(feature)Core") : featureSourceDir
        let uiDir = module ? featureSourceDir.appendingPathComponent("\(feature)UI") : featureSourceDir
        let featureTestDir = testTarget.directoryURL.appendingPathComponent(pathOption).appendingPathComponent(feature)

        var writes: [(url: URL, contents: String)] = []

        if noLogic {
            writes.append((uiDir.appendingPathComponent("\(feature)View.swift"), Self.noLogicView(feature: feature)))
            writes.append(
                (uiDir.appendingPathComponent("\(feature)ViewModel.swift"), Self.noLogicViewModel(feature: feature))
            )
            writes.append(
                (
                    featureSourceDir.appendingPathComponent("\(feature)Module.swift"),
                    Self.noLogicModule(feature: feature)
                )
            )
            if !noTests {
                writes.append(
                    (
                        featureTestDir.appendingPathComponent("\(feature)ViewModelTests.swift"),
                        Self.noLogicViewModelTests(feature: feature, module: target.moduleName)
                    )
                )
            }
        } else {
            writes.append((uiDir.appendingPathComponent("\(feature)View.swift"), try render("View.swift.txt")))
            writes.append(
                (uiDir.appendingPathComponent("\(feature)ViewModel.swift"), try render("ViewModel.swift.txt"))
            )
            writes.append((coreDir.appendingPathComponent("\(feature)Logic.swift"), try render("Logic.swift.txt")))
            if api {
                writes.append(
                    (
                        coreDir.appendingPathComponent("Services").appendingPathComponent("\(feature)Service.swift"),
                        try render("Service.swift.txt")
                    )
                )
            }
            if local {
                writes.append(
                    (
                        coreDir.appendingPathComponent("Stores").appendingPathComponent("\(feature)Store.swift"),
                        try render("Store.swift.txt")
                    )
                )
            }
            writes.append(
                (featureSourceDir.appendingPathComponent("\(feature)Module.swift"), try render("Module.swift.txt"))
            )

            if !noTests {
                writes.append(
                    (
                        featureTestDir.appendingPathComponent("\(feature)ViewModelTests.swift"),
                        try render("ViewModelTests.swift.txt")
                    )
                )
                writes.append(
                    (
                        featureTestDir.appendingPathComponent("Mocks")
                            .appendingPathComponent("\(feature)LogicMock.swift"),
                        try render("LogicMock.swift.txt")
                    )
                )
                writes.append(
                    (
                        featureTestDir.appendingPathComponent("\(feature)LogicTests.swift"),
                        try render("LogicTests.swift.txt")
                    )
                )
                if api {
                    writes.append(
                        (
                            featureTestDir.appendingPathComponent("Mocks")
                                .appendingPathComponent("\(feature)ServiceMock.swift"),
                            try render("ServiceMock.swift.txt")
                        )
                    )
                    writes.append(
                        (
                            featureTestDir.appendingPathComponent("Services")
                                .appendingPathComponent("\(feature)ServiceTests.swift"),
                            try render("ServiceTests.swift.txt")
                        )
                    )
                }
                if local {
                    writes.append(
                        (
                            featureTestDir.appendingPathComponent("Mocks")
                                .appendingPathComponent("InMemory\(feature)Store.swift"),
                            try render("InMemoryStore.swift.txt")
                        )
                    )
                    writes.append(
                        (
                            featureTestDir.appendingPathComponent("Stores")
                                .appendingPathComponent("\(feature)StoreTests.swift"),
                            try render("StoreTests.swift.txt")
                        )
                    )
                }
            }
        }

        if dryRun {
            print("generate-feature \(feature) --dry-run (nada se escribe):")
            for write in writes {
                print("  \(Self.displayPath(write.url, root: context.package.directoryURL))")
            }
            return
        }

        for write in writes {
            try FileManager.default.createDirectory(
                at: write.url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try write.contents.write(to: write.url, atomically: true, encoding: .utf8)
            print("Creado \(Self.displayPath(write.url, root: context.package.directoryURL))")
        }

        Self.printNextSteps(
            feature: feature,
            featureLower: featureLower,
            module: module,
            noLogic: noLogic,
            route: routeOption,
            targetName: target.name
        )
    }

    // MARK: - Target discovery

    private static func selectTarget(_ package: Package, named name: String?) -> SourceModuleTarget? {
        let sourceTargets = package.targets.compactMap { $0 as? SourceModuleTarget }.filter { $0.kind != .test }
        if let name {
            return sourceTargets.first { $0.name == name }
        }
        return sourceTargets.first { $0.kind == .generic } ?? sourceTargets.first
    }

    private static func testTarget(for target: SourceModuleTarget, in package: Package) -> SourceModuleTarget? {
        let testTargets = package.targets.compactMap { $0 as? SourceModuleTarget }.filter { $0.kind == .test }
        if let byName = testTargets.first(where: { $0.name == "\(target.name)Tests" }) {
            return byName
        }
        return testTargets.first
    }

    /// AppFoundation's `Templates/` directory, located through the package dependency
    /// graph rather than bundled as a plugin resource — the templates are plain text a
    /// human/agent reads directly from AppFoundation's own checkout
    /// (`ARQUITECTURA-KIT-2026-09-02.md` §3).
    private static func findTemplatesDirectory(in package: Package) -> URL? {
        if package.displayName == "AppFoundation" {
            let local = package.directoryURL.appendingPathComponent("Templates")
            if FileManager.default.fileExists(atPath: local.path) { return local }
        }
        for dependency in package.dependencies {
            if let found = findTemplatesDirectory(in: dependency.package) {
                return found
            }
        }
        return nil
    }

    // MARK: - Naming

    private static func pascalCase(_ raw: String) -> String {
        guard let first = raw.first else { return raw }
        return String(first).uppercased() + raw.dropFirst()
    }

    private static func camelCase(_ pascal: String) -> String {
        guard let first = pascal.first else { return pascal }
        return String(first).lowercased() + pascal.dropFirst()
    }

    private static func displayPath(_ url: URL, root: URL) -> String {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return url.path.hasPrefix(rootPath) ? String(url.path.dropFirst(rootPath.count)) : url.path
    }

    // MARK: - Next steps (never automated: no `.xcodeproj`/`AppRoute` edits, PRD-AF-08)

    private static func printNextSteps(
        feature: String,
        featureLower: String,
        module: Bool,
        noLogic: Bool,
        route: String?,
        targetName: String
    ) {
        print("")
        print("Pasos manuales — generate-feature nunca edita el .xcodeproj ni el enum AppRoute:")
        print("  1. Añade un case a tu enum AppRoute: case \(featureLower)")
        print("     y regístralo donde tu CoordinatorView resuelve rutas → vistas.")
        print("  2. Registra el composition root en el arranque de la app:")
        print("     Container.shared.register(modules: [\(feature)Module(...)])")
        if let route {
            print("     (ruta indicada: \(route))")
        }
        print("  3. Si tu proyecto usa carpetas sincronizadas de Xcode 16, Xcode recoge los")
        print("     ficheros nuevos solo; si no, arrastra la carpeta generada al target '\(targetName)'.")
        if module {
            print("")
            print("--module (M8): los ficheros se separaron en \(feature)Core/ y \(feature)UI/ dentro")
            print("de este mismo target — generate-feature NO edita Package.swift para crear targets")
            print("nuevos. Para que el compilador imponga la dirección de dependencias de verdad,")
            print("promueve ambas carpetas a targets propios:")
            print(
                """
                    .target(name: "\(feature)Core", dependencies: ["CoreNetworking"], path: "Features/\(feature)/\(feature)Core"),
                    .target(name: "\(feature)UI", dependencies: ["AppFoundation", "\(feature)Core"], path: "Features/\(feature)/\(feature)UI"),
                """
            )
        }
        if noLogic {
            print("")
            print("--no-logic: \(feature)ViewModel hereda de BaseViewModel directamente, sin Logic —")
            print("usa esto solo para una pantalla realmente sin regla de negocio propia.")
        }
    }
}

enum GenerateFeatureError: Error, CustomStringConvertible {
    case missingFeatureName
    case templatesNotFound
    case templateMissing(String)
    case noTarget
    case noTestTarget(String)

    var description: String {
        switch self {
        case .missingFeatureName:
            return "Falta el nombre del feature: swift package generate-feature <Nombre> [--api] [--local] …"
        case .templatesNotFound:
            return "No se encontró AppFoundation/Templates — ¿AppFoundation es una dependencia de este paquete?"
        case .templateMissing(let name):
            return "Falta la plantilla '\(name)' en AppFoundation/Templates."
        case .noTarget:
            return "No se encontró un target de origen (no-test) donde generar el feature. Usa --target NAME."
        case .noTestTarget(let name):
            return "No se encontró un target de tests para '\(name)'. Usa --no-tests para omitir los tests generados."
        }
    }
}
