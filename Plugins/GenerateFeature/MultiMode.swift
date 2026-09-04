import Foundation
import PackagePlugin

// `ManifestEditor` is not imported from a dependency, same reason as `TemplateEngine`
// (see the note at the top of `plugin.swift`): `ManifestEditor.swift` in this directory is
// a symlink to `Sources/GenerateFeatureSupport/ManifestEditor.swift`.

/// PRD-AF-10, entregable 2: `generate-feature` aware of multi-module mode. Multi mode is
/// detected by a `.archinit-multi` marker file in the `Features` package root — written by
/// `archinit --multi` (agent A's job, not built here; see `Scripts/verify-generator.sh`'s
/// "modo multi" block for the exact fixture shape — `.archinit-multi`, the
/// `// archinit:features-begin/end` and `// archinit:products-begin/end` markers in
/// `Package.swift`, `// archinit:modules` in `../../App/AppModule.swift`, and
/// `// archinit:routes` in `../../App/AppRoute.swift` — that this code is exercised
/// against). In this mode each feature is a real SwiftPM target (two, with `--module`)
/// instead of a subfolder inside an existing one, and `generate-feature` registers it
/// between markers — the only manifest edit this generator ever makes.
extension GenerateFeaturePlugin {
    static func isMultiMode(package: Package) -> Bool {
        let marker = package.directoryURL.appendingPathComponent(".archinit-multi")
        return FileManager.default.fileExists(atPath: marker.path)
    }

    // MARK: - Entry point

    /// The whole multi-mode `generate-feature` flow: compute the layout, validate the
    /// `Package.swift` registration BEFORE touching disk (so a missing marker or an
    /// already-registered target aborts with nothing written at all), render every file,
    /// and — unless `--no-register` — write the updated manifest and best-effort edit
    /// `../../App/{AppModule,AppRoute}.swift`.
    ///
    /// `render`'s type drops `render(_:module:splitModule:coreModule:)`'s argument labels
    /// and defaults (passing a nested function as a value does that in Swift) — every call
    /// site below spells out all four positional arguments.
    static func performMultiMode(
        context: PluginContext,
        feature: String,
        featureLower: String,
        api: Bool,
        module: Bool,
        noLogic: Bool,
        noTests: Bool,
        dryRun: Bool,
        noRegister: Bool,
        newService: Bool,
        newStore: Bool,
        noServiceFlag: Bool,
        noStoreFlag: Bool,
        serviceFrom: String?,
        storeFrom: String?,
        render: (String, String?, Bool, String?) throws -> String
    ) throws {
        let packageRoot = context.package.directoryURL
        let layout = Self.multiLayout(feature: feature, module: module, packageRoot: packageRoot)

        // Validate first: if this throws, NOTHING below has run yet — no generated file,
        // no manifest write. That is what makes "sin tocar nada" true.
        var registeredManifestText: String?
        if !noRegister {
            registeredManifestText = try Self.registeredManifestText(
                feature: feature,
                module: module,
                api: api,
                layout: layout,
                packageRoot: packageRoot
            )
        }

        var writes: [(url: URL, contents: String)] = []
        if noLogic {
            writes.append(
                (layout.uiDir.appendingPathComponent("\(feature)View.swift"), Self.noLogicView(feature: feature))
            )
            writes.append(
                (
                    layout.uiDir.appendingPathComponent("\(feature)ViewModel.swift"),
                    Self.noLogicViewModel(feature: feature)
                )
            )
            writes.append(
                (
                    layout.moduleFileDir.appendingPathComponent("\(feature)Module.swift"),
                    Self.noLogicModule(feature: feature)
                )
            )
            if !noTests {
                writes.append(
                    (
                        layout.testDir.appendingPathComponent("\(feature)ViewModelTests.swift"),
                        Self.noLogicViewModelTests(feature: feature, module: layout.uiTargetName)
                    )
                )
            }
        } else {
            writes.append(
                (
                    layout.uiDir.appendingPathComponent("\(feature)View.swift"),
                    try render("View.swift.txt", nil, module, layout.coreTargetName)
                )
            )
            writes.append(
                (
                    layout.uiDir.appendingPathComponent("\(feature)ViewModel.swift"),
                    try render("ViewModel.swift.txt", nil, module, layout.coreTargetName)
                )
            )
            writes.append(
                (
                    layout.coreDir.appendingPathComponent("\(feature)Logic.swift"),
                    try render("Logic.swift.txt", nil, false, nil)
                )
            )
            if newService {
                writes.append(
                    (
                        layout.coreDir.appendingPathComponent("Services")
                            .appendingPathComponent("\(feature)Service.swift"),
                        try render("Service.swift.txt", nil, false, nil)
                    )
                )
            }
            if newStore {
                writes.append(
                    (
                        layout.coreDir.appendingPathComponent("Stores").appendingPathComponent("\(feature)Store.swift"),
                        try render("Store.swift.txt", nil, false, nil)
                    )
                )
            }
            writes.append(
                (
                    layout.moduleFileDir.appendingPathComponent("\(feature)Module.swift"),
                    try render("Module.swift.txt", nil, module, layout.coreTargetName)
                )
            )

            if !noTests {
                writes.append(
                    (
                        layout.testDir.appendingPathComponent("\(feature)ViewModelTests.swift"),
                        try render("ViewModelTests.swift.txt", layout.uiTargetName, module, layout.coreTargetName)
                    )
                )
                writes.append(
                    (
                        layout.testDir.appendingPathComponent("Mocks")
                            .appendingPathComponent("\(feature)LogicMock.swift"),
                        try render("LogicMock.swift.txt", layout.coreTargetName, false, nil)
                    )
                )
                writes.append(
                    (
                        layout.testDir.appendingPathComponent("\(feature)LogicTests.swift"),
                        try render("LogicTests.swift.txt", layout.coreTargetName, false, nil)
                    )
                )
                if newService {
                    writes.append(
                        (
                            layout.testDir.appendingPathComponent("Mocks")
                                .appendingPathComponent("\(feature)ServiceMock.swift"),
                            try render("ServiceMock.swift.txt", layout.coreTargetName, false, nil)
                        )
                    )
                    writes.append(
                        (
                            layout.testDir.appendingPathComponent("Services")
                                .appendingPathComponent("\(feature)ServiceTests.swift"),
                            try render("ServiceTests.swift.txt", layout.coreTargetName, false, nil)
                        )
                    )
                }
                if newStore {
                    writes.append(
                        (
                            layout.testDir.appendingPathComponent("Mocks")
                                .appendingPathComponent("InMemory\(feature)Store.swift"),
                            try render("InMemoryStore.swift.txt", layout.coreTargetName, false, nil)
                        )
                    )
                    writes.append(
                        (
                            layout.testDir.appendingPathComponent("Stores")
                                .appendingPathComponent("\(feature)StoreTests.swift"),
                            try render("StoreTests.swift.txt", layout.coreTargetName, false, nil)
                        )
                    )
                }
            }
        }

        if dryRun {
            print("generate-feature \(feature) --dry-run (modo multi, nada se escribe):")
            for write in writes {
                print("  \(Self.displayPath(write.url, root: packageRoot))")
            }
            if !noRegister {
                let uiSuffix = module ? " + \(layout.uiTargetName)" : ""
                print(
                    "  Package.swift: registraría \(layout.coreTargetName)\(uiSuffix) + \(layout.testTargetName) "
                        + "+ producto \(feature)Feature"
                )
            }
            return
        }

        for write in writes {
            try FileManager.default.createDirectory(
                at: write.url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try write.contents.write(to: write.url, atomically: true, encoding: .utf8)
            print("Creado \(Self.displayPath(write.url, root: packageRoot))")
        }

        if let registeredManifestText {
            let manifestURL = packageRoot.appendingPathComponent("Package.swift")
            try registeredManifestText.write(to: manifestURL, atomically: true, encoding: .utf8)
            let uiSuffix = module ? " + \(layout.uiTargetName)" : ""
            print(
                "Registrado en Package.swift: \(layout.coreTargetName)\(uiSuffix) + \(layout.testTargetName) "
                    + "+ producto \(feature)Feature"
            )
        }

        var moduleOutcome: AppEditOutcome?
        var routeOutcome: AppEditOutcome?
        if !noRegister {
            let appDir = Self.appDirectory(fromFeaturesPackage: packageRoot)
            let moduleExpression = Self.moduleInitExpression(feature: feature, packageRoot: packageRoot)
            moduleOutcome = Self.registerAppModule(
                feature: feature,
                expression: moduleExpression,
                appDirectory: appDir
            )
            routeOutcome = Self.registerAppRoute(featureLower: featureLower, appDirectory: appDir)
            for outcome in Self.registerAppWiring(
                feature: feature,
                featureLower: featureLower,
                appDirectory: appDir,
                repoRoot: appDir.deletingLastPathComponent()
            ) {
                print(outcome)
            }
        }

        Self.printMultiNextSteps(
            feature: feature,
            featureLower: featureLower,
            module: module,
            layout: layout,
            noRegister: noRegister,
            moduleOutcome: moduleOutcome,
            routeOutcome: routeOutcome,
            noLogic: noLogic,
            noService: noServiceFlag,
            noStore: noStoreFlag,
            serviceFrom: serviceFrom,
            storeFrom: storeFrom
        )
    }

    /// Where every generated file lands in multi mode. Without `--module`, `coreDir` and
    /// `uiDir` are the same directory (one real target, `<Feature>Feature`) — identical in
    /// spirit to the non-multi `--module` split, just at the target level instead of a
    /// subfolder. With `--module`, `<Feature>Module.swift` lives in `uiDir`: it
    /// constructs a `<Feature>ViewModel` (a UI-only type), so it cannot live in Core
    /// without an illegal Core → UI dependency; it reaches Core's `Servicing`/`Storing`/
    /// `Logic` types through the cross-module import `View.swift.txt`/`ViewModel.swift.txt`/
    /// `Module.swift.txt` add under the `splitModule` flag.
    struct MultiLayout {
        let coreTargetName: String
        let uiTargetName: String
        let testTargetName: String
        let coreDir: URL
        let uiDir: URL
        let moduleFileDir: URL
        let testDir: URL
    }

    static func multiLayout(feature: String, module: Bool, packageRoot: URL) -> MultiLayout {
        let coreTargetName = module ? "\(feature)FeatureCore" : "\(feature)Feature"
        let uiTargetName = module ? "\(feature)FeatureUI" : "\(feature)Feature"
        let sourcesDir = packageRoot.appendingPathComponent("Sources")
        let coreDir = sourcesDir.appendingPathComponent(coreTargetName)
        let uiDir = sourcesDir.appendingPathComponent(uiTargetName)
        let testTargetName = "\(feature)FeatureTests"
        let testDir = packageRoot.appendingPathComponent("Tests").appendingPathComponent(testTargetName)
        return MultiLayout(
            coreTargetName: coreTargetName,
            uiTargetName: uiTargetName,
            testTargetName: testTargetName,
            coreDir: coreDir,
            uiDir: uiDir,
            moduleFileDir: module ? uiDir : coreDir,
            testDir: testDir
        )
    }

    enum MultiModeError: Error, CustomStringConvertible {
        case manifestNotReadable(String)
        case alreadyRegistered(String)

        var description: String {
            switch self {
            case .manifestNotReadable(let path):
                return "No se pudo leer '\(path)' como UTF-8 — ¿es el Package.swift del paquete Features?"
            case .alreadyRegistered(let message):
                return message
            }
        }
    }

    // MARK: - Package.swift registration

    /// Builds the `.target`/`.testTarget`/`.library` snippets for `feature` and computes
    /// the resulting `Package.swift` text — WITHOUT writing anything. Throws
    /// `ManifestEditor.EditError.markerNotFound` if a marker is missing, or
    /// `MultiModeError.alreadyRegistered` if the target/product is already there. Callers
    /// run this BEFORE writing any generated source file, so a failure here leaves the
    /// working tree completely untouched (PRD-AF-10: "si los markers no están o el target
    /// ya existe, error claro sin tocar nada").
    static func registeredManifestText(
        feature: String,
        module: Bool,
        api: Bool,
        layout: MultiLayout,
        packageRoot: URL
    ) throws -> String {
        let manifestURL = packageRoot.appendingPathComponent("Package.swift")
        guard let data = FileManager.default.contents(atPath: manifestURL.path),
            let originalText = String(data: data, encoding: .utf8)
        else {
            throw MultiModeError.manifestNotReadable(manifestURL.path)
        }

        let swiftLintLiteral = ManifestEditor.existingPluginLiteral(named: "SwiftLintBuildToolPlugin", in: originalText)
        // `ArchitectureLint` (the BUILD-TOOL plugin, run automatically by `swift build`)
        // scans one target's `sourceFiles` at a time — unlike `swift package archlint`
        // (the COMMAND plugin), which walks the whole package directory together. R5 ("a
        // ViewModel has its Logic") is a cross-file check *within that one scan*: a split
        // `<Feature>FeatureUI` target has a ViewModel but its Logic lives in
        // `<Feature>FeatureCore` — a different target, a different scan — so attaching the
        // build-tool plugin to UI-in-split-mode would make `swift build` fail on a false
        // R5 positive that `Sources/archlint` doesn't know how to resolve (out of scope
        // here: R13, the module-isolation rule that DOES know about the Core/UI split, is
        // a different agent's PRD-AF-10 deliverable). Core never triggers R5 (it has no
        // ViewModel file to pair), so it always keeps the plugin; UI only keeps it when
        // there is no split (non-`--module`, where Core and UI are the same target and
        // scan). `swift package archlint` still checks UI's R1/R4 for real — see
        // `Scripts/verify-generator.sh`'s "modo multi" block.
        func pluginsLiteral(includeArchitectureLint: Bool) -> [String] {
            var literals: [String] = []
            if includeArchitectureLint {
                literals.append(".plugin(name: \"ArchitectureLint\", package: \"AppFoundation\")")
            }
            if let swiftLintLiteral { literals.append(swiftLintLiteral) }
            return literals
        }
        func productDependencies(extra: [String] = []) -> [String] {
            var deps = extra
            deps.append(".product(name: \"AppFoundation\", package: \"AppFoundation\")")
            if api { deps.append(".product(name: \"CoreNetworking\", package: \"CoreNetworking\")") }
            deps.append(".product(name: \"Domain\", package: \"Platform\")")
            return deps
        }

        var entries: [(literal: String, duplicateMarker: String)] = []
        entries.append(
            (
                targetLiteral(
                    name: layout.coreTargetName,
                    dependencies: productDependencies(),
                    path: "Sources/\(layout.coreTargetName)",
                    plugins: pluginsLiteral(includeArchitectureLint: true)
                ),
                "name: \"\(layout.coreTargetName)\""
            )
        )
        if module {
            entries.append(
                (
                    targetLiteral(
                        name: layout.uiTargetName,
                        dependencies: productDependencies(extra: ["\"\(layout.coreTargetName)\""]),
                        path: "Sources/\(layout.uiTargetName)",
                        plugins: pluginsLiteral(includeArchitectureLint: false)
                    ),
                    "name: \"\(layout.uiTargetName)\""
                )
            )
        }
        var testDependencies = ["\"\(layout.coreTargetName)\""]
        if module { testDependencies.append("\"\(layout.uiTargetName)\"") }
        testDependencies.append(".product(name: \"AppFoundationTestSupport\", package: \"AppFoundation\")")
        if api { testDependencies.append(".product(name: \"CoreNetworkingTestSupport\", package: \"CoreNetworking\")") }
        entries.append(
            (
                testTargetLiteral(
                    name: layout.testTargetName,
                    dependencies: testDependencies,
                    path: "Tests/\(layout.testTargetName)"
                ),
                "name: \"\(layout.testTargetName)\""
            )
        )

        var text = originalText
        for (literal, duplicateMarker) in entries {
            switch try ManifestEditor.insertBetweenMarkers(
                literal,
                duplicateMarker: duplicateMarker,
                beginMarker: "// archinit:features-begin",
                endMarker: "// archinit:features-end",
                in: text
            ) {
            case .inserted(let newText):
                text = newText
            case .alreadyPresent:
                throw MultiModeError.alreadyRegistered(
                    "'\(duplicateMarker)' ya está registrado en Package.swift entre los markers de targets — "
                        + "generate-feature no ha tocado nada. Borra esa entrada primero si quieres regenerar el feature."
                )
            }
        }

        let productName = "\(feature)Feature"
        let productTargets = module ? [layout.coreTargetName, layout.uiTargetName] : [layout.coreTargetName]
        switch try ManifestEditor.insertBetweenMarkers(
            libraryProductLiteral(name: productName, targets: productTargets),
            duplicateMarker: "name: \"\(productName)\"",
            beginMarker: "// archinit:products-begin",
            endMarker: "// archinit:products-end",
            in: text
        ) {
        case .inserted(let newText):
            text = newText
        case .alreadyPresent:
            throw MultiModeError.alreadyRegistered(
                "El producto '\(productName)' ya está registrado en Package.swift entre los markers de products — "
                    + "generate-feature no ha tocado nada."
            )
        }

        return text
    }

    private static func targetLiteral(name: String, dependencies: [String], path: String, plugins: [String]) -> String {
        var lines = [".target("]
        lines.append("    name: \"\(name)\",")
        lines.append("    dependencies: [")
        for dependency in dependencies { lines.append("        \(dependency),") }
        lines.append("    ],")
        lines.append("    path: \"\(path)\",")
        if plugins.isEmpty {
            lines.append("    swiftSettings: swiftSettings")
        } else {
            lines.append("    swiftSettings: swiftSettings,")
            lines.append("    plugins: [")
            for plugin in plugins { lines.append("        \(plugin),") }
            lines.append("    ]")
        }
        lines.append("),")
        return lines.joined(separator: "\n")
    }

    private static func testTargetLiteral(name: String, dependencies: [String], path: String) -> String {
        var lines = [".testTarget("]
        lines.append("    name: \"\(name)\",")
        lines.append("    dependencies: [")
        for dependency in dependencies { lines.append("        \(dependency),") }
        lines.append("    ],")
        lines.append("    path: \"\(path)\",")
        lines.append("    swiftSettings: swiftSettings")
        lines.append("),")
        return lines.joined(separator: "\n")
    }

    private static func libraryProductLiteral(name: String, targets: [String]) -> String {
        let targetsList = targets.map { "\"\($0)\"" }.joined(separator: ", ")
        return ".library(name: \"\(name)\", targets: [\(targetsList)]),"
    }

    // MARK: - App/AppModule.swift, App/AppRoute.swift (best-effort — "solo si esos
    // ficheros y markers existen; si no, imprime los pasos manuales como hoy")

    enum AppEditOutcome {
        case registered
        case alreadyPresent
        case skipped(reason: String)

        func describe(_ what: String) -> String {
            switch self {
            case .registered: return "\(what) añadido"
            case .alreadyPresent: return "\(what) ya estaba"
            case .skipped(let reason): return "\(what) NO añadido (\(reason)) — hazlo a mano"
            }
        }
    }

    /// `../../App` relative to the `Features` package root (PRD-AF-10's tree: `App/` and
    /// `Packages/Features/` are siblings under the repo root).
    static func appDirectory(fromFeaturesPackage packageRoot: URL) -> URL {
        packageRoot.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("App")
    }

    /// The composition-root expression for the module just generated, read from its real
    /// `public init` (see `ManifestEditor.moduleInitExpression`). Falls back to `Feature()`
    /// if the module file cannot be found (e.g. `--no-register` layouts).
    static func moduleInitExpression(feature: String, packageRoot: URL) -> String {
        let sources = packageRoot.appendingPathComponent("Sources")
        let fileManager = FileManager.default
        if let enumerator = fileManager.enumerator(at: sources, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where url.lastPathComponent == "\(feature)Module.swift" {
                if let data = fileManager.contents(atPath: url.path), let text = String(data: data, encoding: .utf8) {
                    return ManifestEditor.moduleInitExpression(
                        feature: feature,
                        moduleSource: text,
                        baseURLExpression: "AppModule.apiBaseURL"
                    )
                }
            }
        }
        return "\(feature)Module()"
    }

    /// Best-effort wiring beyond the module and the route: the `import` of the feature in
    /// `AppModule.swift` and `RootView.swift`, the navigation destination in `RootView.swift`,
    /// and the feature product in `project.yml` — each only if its marker exists. Returns one
    /// human-readable line per edit for the plugin's output.
    static func registerAppWiring(feature: String, featureLower: String, appDirectory: URL, repoRoot: URL) -> [String] {
        var lines: [String] = []
        let importLine = "import \(feature)Feature"
        for file in ["AppModule.swift", "RootView.swift"] {
            let outcome = insertAtMarker(
                importLine,
                duplicateOf: importLine,
                marker: "// archinit:imports",
                file: appDirectory.appendingPathComponent(file)
            )
            lines.append("App/\(file): \(outcome.describe("\(importLine)"))")
        }
        let destination = "case .\(featureLower): \(feature)View(viewModel: Container.shared.resolve())"
        let destinationOutcome = insertAtMarker(
            destination,
            duplicateOf: "case .\(featureLower):",
            marker: "// archinit:destinations",
            file: appDirectory.appendingPathComponent("RootView.swift")
        )
        lines.append("App/RootView.swift: \(destinationOutcome.describe("destino \(feature)View"))")
        // Relative indent inside the entry: the editor shifts the whole block by the marker's indent.
        let productOutcome = insertAtMarker(
            "- package: Features\n  product: \(feature)Feature",
            duplicateOf: "product: \(feature)Feature",
            marker: "# archinit:products",
            file: repoRoot.appendingPathComponent("project.yml")
        )
        lines.append("project.yml: \(productOutcome.describe("producto \(feature)Feature"))")
        return lines
    }

    private static func insertAtMarker(
        _ entry: String,
        duplicateOf: String,
        marker: String,
        file: URL
    ) -> AppEditOutcome {
        guard let data = FileManager.default.contents(atPath: file.path), let text = String(data: data, encoding: .utf8)
        else {
            return .skipped(reason: "no existe \(file.lastPathComponent)")
        }
        guard
            let result = try? ManifestEditor.insertBeforeMarker(
                entry,
                duplicateOf: duplicateOf,
                marker: marker,
                in: text
            )
        else {
            return .skipped(reason: "\(file.lastPathComponent) no tiene el marker '\(marker)'")
        }
        switch result {
        case .inserted(let newText):
            guard (try? newText.write(to: file, atomically: true, encoding: .utf8)) != nil else {
                return .skipped(reason: "no se pudo escribir \(file.lastPathComponent)")
            }
            return .registered
        case .alreadyPresent:
            return .alreadyPresent
        }
    }

    static func registerAppModule(feature: String, expression: String, appDirectory: URL) -> AppEditOutcome {
        let url = appDirectory.appendingPathComponent("AppModule.swift")
        guard let data = FileManager.default.contents(atPath: url.path), let text = String(data: data, encoding: .utf8)
        else {
            return .skipped(reason: "no existe App/AppModule.swift")
        }
        guard
            let result = try? ManifestEditor.insertBeforeMarker(
                "\(expression),",
                duplicateOf: "\(feature)Module(",
                marker: "// archinit:modules",
                in: text
            )
        else {
            return .skipped(reason: "App/AppModule.swift no tiene el marker '// archinit:modules'")
        }
        switch result {
        case .inserted(let newText):
            guard (try? newText.write(to: url, atomically: true, encoding: .utf8)) != nil else {
                return .skipped(reason: "no se pudo escribir App/AppModule.swift")
            }
            return .registered
        case .alreadyPresent:
            return .alreadyPresent
        }
    }

    static func registerAppRoute(featureLower: String, appDirectory: URL) -> AppEditOutcome {
        let url = appDirectory.appendingPathComponent("AppRoute.swift")
        guard let data = FileManager.default.contents(atPath: url.path), let text = String(data: data, encoding: .utf8)
        else {
            return .skipped(reason: "no existe App/AppRoute.swift")
        }
        guard
            let result = try? ManifestEditor.insertBeforeMarker(
                "case \(featureLower)",
                duplicateOf: "case \(featureLower)",
                marker: "// archinit:routes",
                in: text
            )
        else {
            return .skipped(reason: "App/AppRoute.swift no tiene el marker '// archinit:routes'")
        }
        switch result {
        case .inserted(let newText):
            guard (try? newText.write(to: url, atomically: true, encoding: .utf8)) != nil else {
                return .skipped(reason: "no se pudo escribir App/AppRoute.swift")
            }
            return .registered
        case .alreadyPresent:
            return .alreadyPresent
        }
    }

    // MARK: - Next steps (multi mode)

    static func printMultiNextSteps(
        feature: String,
        featureLower: String,
        module: Bool,
        layout: MultiLayout,
        noRegister: Bool,
        moduleOutcome: AppEditOutcome?,
        routeOutcome: AppEditOutcome?,
        noLogic: Bool,
        noService: Bool,
        noStore: Bool,
        serviceFrom: String?,
        storeFrom: String?
    ) {
        print("")
        print(
            "Modo multi: \(layout.coreTargetName)" + (module ? " + \(layout.uiTargetName)" : "")
                + " + \(layout.testTargetName)"
        )
        if noRegister {
            print("--no-register: no se editó Package.swift ni App/ — registra el target, el módulo y la ruta a mano.")
        } else {
            print("Registrado entre los markers de Package.swift (targets: y products:).")
            Self.printAppEditOutcome(
                outcome: moduleOutcome,
                subject: "App/AppModule.swift",
                entry: "\(feature)Module()"
            )
            Self.printAppEditOutcome(
                outcome: routeOutcome,
                subject: "App/AppRoute.swift",
                entry: "case \(featureLower)"
            )
        }
        if noLogic {
            print("")
            print("--no-logic: \(feature)ViewModel hereda de BaseViewModel directamente, sin Logic —")
            print("usa esto solo para una pantalla realmente sin regla de negocio propia.")
        }
        if noService {
            print("")
            print("--no-service: no se generó \(feature)Service — \(feature)Logic depende de 'any")
            print("\(feature)Servicing', declarado como placeholder en \(feature)Logic.swift.")
        }
        if noStore {
            print("")
            print("--no-store: no se generó \(feature)Store — \(feature)Logic depende de 'any")
            print("\(feature)Storing', declarado como placeholder en \(feature)Logic.swift.")
        }
        if let serviceFrom {
            print("")
            print("--service-from \(serviceFrom): \(feature)Logic depende de 'any \(serviceFrom)Servicing'. En modo")
            print("multi cada feature tiene su propio target de tests — si \(serviceFrom)ServiceMock no es")
            print("visible desde \(layout.testTargetName), hazlo público o genera \(feature)LogicTests a mano.")
        }
        if let storeFrom {
            print("")
            print("--store-from \(storeFrom): \(feature)Logic depende de 'any \(storeFrom)Storing'. Misma nota que")
            print("--service-from sobre la visibilidad del mock entre targets de tests distintos en modo multi.")
        }
    }

    private static func printAppEditOutcome(outcome: AppEditOutcome?, subject: String, entry: String) {
        switch outcome {
        case .registered:
            print("\(subject): añadido '\(entry)'.")
        case .alreadyPresent:
            print("\(subject): '\(entry)' ya estaba registrado — nada que hacer.")
        case .skipped(let reason):
            print("\(subject): \(reason) — añade '\(entry)' a mano.")
        case nil:
            break
        }
    }
}
