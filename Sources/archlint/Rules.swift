import Foundation

/// Which layer a file belongs to, decided purely from its name/path — the same convention
/// the generator writes: `XxxViewModel.swift`,
/// `XxxView.swift`, `XxxLogic.swift`, `Services/XxxService.swift`, `Stores/XxxStore.swift`,
/// `XxxModule.swift` (composition root — exempt from most rules, since naming every
/// concrete type is its entire job). Anything under `Tests/`, or named `*Tests.swift`/
/// `*Mock(s).swift`/`*Spy.swift`/`*Stub.swift`, is ignored by the default config before it
/// ever reaches this categorizer.
enum Layer: Equatable {
    case viewModel
    case view
    case logic
    case service
    case store
    case module
    case other

    static func classify(relativePath: String, config: ArchLintConfig) -> Layer {
        let filename = (relativePath as NSString).lastPathComponent
        let stem = filename.hasSuffix(".swift") ? String(filename.dropLast(6)) : filename

        if stem.hasSuffix(config.moduleSuffix) { return .module }
        if stem.hasSuffix(config.viewModelSuffix) { return .viewModel }
        if stem.hasSuffix("View") { return .view }
        if stem.hasSuffix(config.logicSuffix) { return .logic }
        if relativePath.contains("/Services/") || stem.hasSuffix(config.serviceSuffix) { return .service }
        if relativePath.contains("/Stores/") || stem.hasSuffix(config.storeSuffix) { return .store }
        return .other
    }
}

/// Runs every enabled rule over every parsed file and returns the diagnostics, sorted for
/// stable output (path, then line, then column).
enum RuleEngine {
    static func run(files: [ParsedFile], config: ArchLintConfig) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        let layers = Dictionary(
            uniqueKeysWithValues: files.map {
                ($0.relativePath, Layer.classify(relativePath: $0.relativePath, config: config))
            }
        )

        for file in files {
            let layer = layers[file.relativePath] ?? .other
            if config.isEnabled("R1"), layer == .viewModel { diagnostics += checkR1(file, config: config) }
            if config.isEnabled("R2"), layer == .logic { diagnostics += checkR2(file) }
            if config.isEnabled("R3") { diagnostics += checkR3(file, layer: layer) }
            if config.isEnabled("R4"), layer == .view { diagnostics += checkR4(file) }
            if config.isEnabled("R6") { diagnostics += checkR6(file, config: config) }
            if config.isEnabled("R7") { diagnostics += checkR7(file, layer: layer) }
            if config.isEnabled("R8") { diagnostics += checkR8(file, layer: layer) }
            if config.isEnabled("R9") { diagnostics += checkR9(file, layer: layer) }
            if config.isEnabled("R10") { diagnostics += checkR10(file, layer: layer) }
            if config.isEnabled("R11"), layer == .logic { diagnostics += checkR11(file) }
            if config.isEnabled("R12"), layer == .view { diagnostics += checkR12(file) }
            if config.isEnabled("R15"), layer == .viewModel { diagnostics += checkR15(file, config: config) }
            if config.isEnabled("R16") { diagnostics += checkR16(file) }
            // R13 applies to every file, regardless of layer — it is about which MODULE a
            // file lives in, not which architectural layer within that module.
            if config.isEnabled("R13") { diagnostics += checkR13(file, config: config) }
        }

        if config.isEnabled("R5") {
            diagnostics += checkR5(files: files, layers: layers, config: config)
        }

        return diagnostics.sorted {
            if $0.path != $1.path { return $0.path < $1.path }
            if $0.line != $1.line { return $0.line < $1.line }
            return $0.col < $1.col
        }
    }

    // MARK: - R1 — ViewModel

    private static func checkR1(_ file: ParsedFile, config: ArchLintConfig) -> [Diagnostic] {
        var out: [Diagnostic] = []

        if let ref = file.imports.first(where: { $0.module == "CoreNetworking" }) {
            out.append(
                Diagnostic(
                    path: file.path,
                    line: ref.line,
                    col: ref.col,
                    severity: .error,
                    rule: "R1",
                    message: "El ViewModel no debe importar CoreNetworking — delega en su Logic (any XxxLogicProtocol)."
                )
            )
        }

        for ref in file.references {
            if ref.name == "APIService" || ref.name == "URLSession" || hasSuffix(ref.name, config.serviceSuffix)
                || hasSuffix(ref.name, config.storeSuffix)
            {
                out.append(
                    Diagnostic(
                        path: file.path,
                        line: ref.line,
                        col: ref.col,
                        severity: .error,
                        rule: "R1",
                        message:
                            "El ViewModel no debe referenciar '\(ref.name)' — solo conoce su Logic a través de 'any XxxLogicProtocol' inyectada por init."
                    )
                )
            }
        }

        if let vmType = file.typeDecls.first(where: {
            $0.keyword == "class" && $0.name.hasSuffix(config.viewModelSuffix)
        }) {
            if !vmType.inherits("ActionHandling") {
                out.append(
                    Diagnostic(
                        path: file.path,
                        line: vmType.line,
                        col: vmType.col,
                        severity: .error,
                        rule: "R1",
                        message:
                            "'\(vmType.name)' debe conformar 'ActionHandling' (handle(_:) es el único punto de entrada de acciones)."
                    )
                )
            }
            if config.strict && !vmType.inherits("LogicViewModel") {
                out.append(
                    Diagnostic(
                        path: file.path,
                        line: vmType.line,
                        col: vmType.col,
                        severity: .error,
                        rule: "R1",
                        message:
                            "strict: true exige heredar de 'LogicViewModel<any XxxLogicProtocol>' en vez de 'BaseViewModel' a pelo."
                    )
                )
            }
        }

        return out
    }

    // MARK: - R2 — Logic

    private static func checkR2(_ file: ParsedFile) -> [Diagnostic] {
        var out: [Diagnostic] = []

        for ref in file.imports where ref.module == "SwiftUI" || ref.module == "UIKit" {
            out.append(
                Diagnostic(
                    path: file.path,
                    line: ref.line,
                    col: ref.col,
                    severity: .error,
                    rule: "R2",
                    message: "La Logic no debe importar '\(ref.module)' — no tiene concepto de vista."
                )
            )
        }

        for ref in file.references where hasSuffix(ref.name, "ViewModel") {
            out.append(
                Diagnostic(
                    path: file.path,
                    line: ref.line,
                    col: ref.col,
                    severity: .error,
                    rule: "R2",
                    message:
                        "La Logic no debe referenciar '\(ref.name)' — la orquestación y la navegación viven en el ViewModel."
                )
            )
        }

        let hasLogicProtocol = file.typeDecls.contains { $0.keyword == "protocol" && $0.inherits("Logic") }
        if !hasLogicProtocol {
            out.append(
                Diagnostic(
                    path: file.path,
                    line: 1,
                    col: 1,
                    severity: .error,
                    rule: "R2",
                    message:
                        "Falta 'protocol XxxLogicProtocol: Logic' — toda Logic declara su propio protocolo marcador."
                )
            )
        }

        return out
    }

    // MARK: - R3 — Service / Store exclusivity

    private static let networkOnlyIdentifiers: Set<String> = ["APIServiceProtocol", "BaseRequest"]
    private static let persistenceOnlyIdentifiers: Set<String> = [
        "ModelContext", "ModelContainer", "UserDefaults", "Keychain", "FileManager"
    ]

    private static func checkR3(_ file: ParsedFile, layer: Layer) -> [Diagnostic] {
        var out: [Diagnostic] = []

        switch layer {
        case .service:
            let hasServicing = file.typeDecls.contains { $0.keyword == "protocol" && $0.name.hasSuffix("Servicing") }
            if !hasServicing {
                out.append(
                    Diagnostic(
                        path: file.path,
                        line: 1,
                        col: 1,
                        severity: .error,
                        rule: "R3",
                        message:
                            "Falta 'protocol XxxServicing: Sendable' — un Service declara su protocolo antes de su implementación."
                    )
                )
            }
        case .store:
            let hasStoring = file.typeDecls.contains { $0.keyword == "protocol" && $0.name.hasSuffix("Storing") }
            if !hasStoring {
                out.append(
                    Diagnostic(
                        path: file.path,
                        line: 1,
                        col: 1,
                        severity: .error,
                        rule: "R3",
                        message:
                            "Falta 'protocol XxxStoring: Sendable' — un Store declara su protocolo antes de su implementación."
                    )
                )
            }
        case .viewModel, .view, .logic:
            for ref in file.references {
                if networkOnlyIdentifiers.contains(ref.name) {
                    out.append(
                        Diagnostic(
                            path: file.path,
                            line: ref.line,
                            col: ref.col,
                            severity: .error,
                            rule: "R3",
                            message: "Solo un Service toca '\(ref.name)' — llama a través de 'any XxxServicing'."
                        )
                    )
                }
                if persistenceOnlyIdentifiers.contains(ref.name) {
                    out.append(
                        Diagnostic(
                            path: file.path,
                            line: ref.line,
                            col: ref.col,
                            severity: .error,
                            rule: "R3",
                            message: "Solo un Store toca '\(ref.name)' — llama a través de 'any XxxStoring'."
                        )
                    )
                }
            }
            for ref in file.imports where ref.module == "SwiftData" || ref.module == "CoreData" {
                out.append(
                    Diagnostic(
                        path: file.path,
                        line: ref.line,
                        col: ref.col,
                        severity: .error,
                        rule: "R3",
                        message: "Solo un Store importa '\(ref.module)' — llama a través de 'any XxxStoring'."
                    )
                )
            }
        case .module, .other:
            break
        }

        return out
    }

    // MARK: - R4 — View

    private static func checkR4(_ file: ParsedFile) -> [Diagnostic] {
        var out: [Diagnostic] = []
        for ref in file.references {
            let name = ref.name
            if name == "APIService" || hasSuffix(name, "Logic") || hasSuffix(name, "Service")
                || hasSuffix(name, "Store")
            {
                // A view's own type ("LoginView") or its ViewModel type ("LoginViewModel")
                // never match these suffixes, so no extra exclusion is needed here.
                out.append(
                    Diagnostic(
                        path: file.path,
                        line: ref.line,
                        col: ref.col,
                        severity: .error,
                        rule: "R4",
                        message:
                            "La View no debe referenciar '\(name)' — solo conoce su ViewModel y envía Action con ActionSender."
                    )
                )
            }
        }
        return out
    }

    // MARK: - R5 — one Logic per ViewModel

    private static func checkR5(files: [ParsedFile], layers: [String: Layer], config: ArchLintConfig) -> [Diagnostic] {
        var out: [Diagnostic] = []
        let logicStems = Set(
            files.compactMap { file -> String? in
                guard layers[file.relativePath] == .logic else { return nil }
                let filename = (file.relativePath as NSString).lastPathComponent
                return filename.hasSuffix(".swift") ? String(filename.dropLast(6)) : filename
            }
        )

        for file in files where layers[file.relativePath] == .viewModel {
            // A ViewModel that inherits `BaseViewModel` directly (never `LogicViewModel<...>`)
            // has no Logic to be missing — that is precisely the `--no-logic` escape hatch
            //, a deliberate choice for a screen with no business rule of its
            // own, not an omission R5 should flag.
            let hasLogicViewModelBase = file.typeDecls.contains {
                $0.keyword == "class" && $0.inherits("LogicViewModel")
            }
            guard hasLogicViewModelBase else { continue }

            let filename = (file.relativePath as NSString).lastPathComponent
            let stem = filename.hasSuffix(".swift") ? String(filename.dropLast(6)) : filename
            guard stem.hasSuffix(config.viewModelSuffix) else { continue }
            let feature = String(stem.dropLast(config.viewModelSuffix.count))
            let expected = feature + config.logicSuffix
            if !logicStems.contains(expected) {
                out.append(
                    Diagnostic(
                        path: file.path,
                        line: 1,
                        col: 1,
                        severity: .error,
                        rule: "R5",
                        message:
                            "'\(stem).swift' no tiene su '\(expected).swift' — cada ViewModel tiene su Logic (desactivable con 'ignore:' por pantalla)."
                    )
                )
            }
        }
        return out
    }

    // MARK: - R6 — no concrete Service/Store/Logic in another layer's init

    private static func checkR6(_ file: ParsedFile, config: ArchLintConfig) -> [Diagnostic] {
        var out: [Diagnostic] = []
        let bannedSuffixes = [config.serviceSuffix, config.storeSuffix, config.logicSuffix]

        for initDecl in file.inits {
            for param in initDecl.params {
                let normalized = Self.normalizeType(param.typeText)
                guard !normalized.isEmpty else { continue }
                if normalized.hasPrefix("any ") || normalized.contains("->") { continue }
                let bareIdentifier = normalized.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") })
                    .first
                guard let bare = bareIdentifier.map(String.init) else { continue }
                if bannedSuffixes.contains(where: { hasSuffix(bare, $0) }) {
                    out.append(
                        Diagnostic(
                            path: file.path,
                            line: param.line,
                            col: param.col,
                            severity: .error,
                            rule: "R6",
                            message:
                                "El parámetro de init tiene el tipo concreto '\(bare)' — inyecta su protocolo con 'any' (p. ej. 'any \(bare)Protocol') en su lugar."
                        )
                    )
                }
            }
        }
        return out
    }

    /// Strips wrapping parens and a trailing `?`/`!` so `(any ErrorPresenting)?` reduces to
    /// `any ErrorPresenting` before checking whether it starts with `any `.
    private static func normalizeType(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespaces)
        var changed = true
        while changed {
            changed = false
            if t.hasSuffix("?") || t.hasSuffix("!") {
                t = String(t.dropLast()).trimmingCharacters(in: .whitespaces)
                changed = true
            }
            if t.hasPrefix("( ") && t.hasSuffix(" )"), balancedWrap(t) {
                t = String(t.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
                changed = true
            } else if t.hasPrefix("("), t.hasSuffix(")"), balancedWrap(t) {
                t = String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                changed = true
            }
        }
        return t
    }

    private static func balancedWrap(_ text: String) -> Bool {
        guard text.hasPrefix("("), text.hasSuffix(")") else { return false }
        var depth = 0
        let chars = Array(text)
        for (idx, c) in chars.enumerated() {
            if c == "(" { depth += 1 }
            if c == ")" {
                depth -= 1
                if depth == 0 && idx != chars.count - 1 { return false }
            }
        }
        return depth == 0
    }

    // MARK: - R7 — domain errors only past Logic (M1)

    private static func checkR7(_ file: ParsedFile, layer: Layer) -> [Diagnostic] {
        guard layer == .viewModel || layer == .view else { return [] }
        var out: [Diagnostic] = []

        for ref in file.references where ref.name == "APIError" {
            out.append(
                Diagnostic(
                    path: file.path,
                    line: ref.line,
                    col: ref.col,
                    severity: .error,
                    rule: "R7",
                    message:
                        "No debe llegar 'APIError' a esta capa — la Logic lo traduce a un 'DomainError' propio del feature."
                )
            )
        }
        for ref in file.imports where ref.module == "CoreNetworking" {
            out.append(
                Diagnostic(
                    path: file.path,
                    line: ref.line,
                    col: ref.col,
                    severity: .error,
                    rule: "R7",
                    message: "'import CoreNetworking' solo está permitido en Logic y Services."
                )
            )
        }
        return out
    }

    // MARK: - R8 — DTOs stop at Service/Store (M2)

    private static func checkR8(_ file: ParsedFile, layer: Layer) -> [Diagnostic] {
        guard layer == .viewModel || layer == .view || layer == .logic else { return [] }
        var out: [Diagnostic] = []
        for ref in file.references {
            if hasSuffix(ref.name, "Request") || hasSuffix(ref.name, "Response") || hasSuffix(ref.name, "DTO") {
                out.append(
                    Diagnostic(
                        path: file.path,
                        line: ref.line,
                        col: ref.col,
                        severity: .error,
                        rule: "R8",
                        message:
                            "'\(ref.name)' es un DTO — se mapea a un modelo de dominio dentro del Service/Store y no sale de ahí."
                    )
                )
            }
        }
        return out
    }

    // MARK: - R9 — no navigation types below the ViewModel (M3)

    private static let navigationIdentifiers: Set<String> = ["Router", "Coordinator", "DeepLink"]

    private static func checkR9(_ file: ParsedFile, layer: Layer) -> [Diagnostic] {
        guard layer == .logic || layer == .service || layer == .store else { return [] }
        var out: [Diagnostic] = []
        for ref in file.references where navigationIdentifiers.contains(ref.name) {
            out.append(
                Diagnostic(
                    path: file.path,
                    line: ref.line,
                    col: ref.col,
                    severity: .error,
                    rule: "R9",
                    message: "'\(ref.name)' es navegación — solo el ViewModel decide a dónde ir, nunca esta capa."
                )
            )
        }
        return out
    }

    // MARK: - R10 — single composition root (M4)

    private static func checkR10(_ file: ParsedFile, layer: Layer) -> [Diagnostic] {
        guard layer == .viewModel || layer == .logic || layer == .service || layer == .store else { return [] }
        var out: [Diagnostic] = []
        let refs = file.references

        for (idx, ref) in refs.enumerated() {
            if ref.name == "Container", idx + 1 < refs.count, refs[idx + 1].name == "shared" {
                out.append(
                    Diagnostic(
                        path: file.path,
                        line: ref.line,
                        col: ref.col,
                        severity: .error,
                        rule: "R10",
                        message:
                            "'Container.shared' no se llama desde aquí — regístralo y resuélvelo desde el XxxModule (composition root)."
                    )
                )
            }
            if ref.name == "resolve" {
                out.append(
                    Diagnostic(
                        path: file.path,
                        line: ref.line,
                        col: ref.col,
                        severity: .error,
                        rule: "R10",
                        message:
                            "'resolve(...)' no se llama desde aquí — las dependencias entran por init, resueltas en el XxxModule."
                    )
                )
            }
            if ref.name == "Inject" {
                out.append(
                    Diagnostic(
                        path: file.path,
                        line: ref.line,
                        col: ref.col,
                        severity: .error,
                        rule: "R10",
                        message: "'@Inject' no se usa aquí — inyecta por init desde el XxxModule (composition root)."
                    )
                )
            }
        }
        return out
    }

    // MARK: - R11 — a Logic pinned to @MainActor (M5, warning)

    private static func checkR11(_ file: ParsedFile) -> [Diagnostic] {
        var out: [Diagnostic] = []
        for type in file.typeDecls where type.keyword == "class" && type.attributes.contains("MainActor") {
            out.append(
                Diagnostic(
                    path: file.path,
                    line: type.line,
                    col: type.col,
                    severity: .warning,
                    rule: "R11",
                    message:
                        "'\(type.name)' es @MainActor — una Logic normalmente es 'nonisolated' (M5); confirma que es intencional."
                )
            )
        }
        return out
    }

    // MARK: - R12 — a View retains its ViewModel with @State (PRD-X-05 A3/A7, warning)

    private static func checkR12(_ file: ParsedFile) -> [Diagnostic] {
        var out: [Diagnostic] = []
        for property in file.properties where property.name == "viewModel" && !property.hasNearbyStateAttribute {
            out.append(
                Diagnostic(
                    path: file.path,
                    line: property.line,
                    col: property.col,
                    severity: .warning,
                    rule: "R12",
                    message:
                        "La View debe retener su ViewModel con `@State` (`_viewModel = State(initialValue:)`); "
                        + "con `let`, un ViewModel transitorio se libera cuando SwiftUI reevalúa el builder de "
                        + "destino y la acción `.load` se pierde."
                )
            )
        }
        return out
    }

    // MARK: - R15 — every ViewModel declares @Observable (PRD-AF-11 A0)

    /// `@Observable` is not inherited: the macro instruments only the stored properties of
    /// the class it is attached to, so a `BaseViewModel`/`LogicViewModel` subclass without
    /// it never notifies SwiftUI about its OWN properties (the view refreshes only when the
    /// inherited `phase`/`activity` happens to change). Silent, and easy to miss.
    private static func checkR15(_ file: ParsedFile, config: ArchLintConfig) -> [Diagnostic] {
        var out: [Diagnostic] = []
        for decl in file.typeDecls
        where decl.keyword == "class" && decl.name.hasSuffix(config.viewModelSuffix)
            && !decl.attributes.contains(where: { $0.hasSuffix("Observable") })
        {
            out.append(
                Diagnostic(
                    path: file.path,
                    line: decl.line,
                    col: decl.col,
                    severity: .error,
                    rule: "R15",
                    message:
                        "'\(decl.name)' debe declarar @Observable: el macro no se hereda de BaseViewModel, y sin él "
                        + "las propiedades propias del ViewModel no refrescan la vista."
                )
            )
        }
        return out
    }

    // MARK: - R16 — every (non-nonisolated) class declares a deinit (PRD-AF-11 A8)

    /// Under `defaultIsolation(MainActor)`, a class WITHOUT an explicit `deinit` gets a
    /// synthesized *isolated* one that, on OS versions older than the toolchain's runtime,
    /// runs through `swift_task_deinitOnExecutorMainActorBackDeploy`; two of those nested
    /// (a ViewModel releasing its Coordinator/Throttler) aborted with a libmalloc double
    /// free on iOS 26.2. An explicit `deinit {}` is nonisolated and avoids the shim.
    /// Per file: one `deinit` covers the classes declared in it (a lexical check, not a
    /// per-type one); `nonisolated` classes and actors are exempt.
    private static func checkR16(_ file: ParsedFile) -> [Diagnostic] {
        guard file.deinitCount == 0 else { return [] }
        var out: [Diagnostic] = []
        for decl in file.typeDecls where decl.keyword == "class" && !decl.modifiers.contains("nonisolated") {
            out.append(
                Diagnostic(
                    path: file.path,
                    line: decl.line,
                    col: decl.col,
                    severity: .error,
                    rule: "R16",
                    message:
                        "'\(decl.name)' necesita un `deinit {}` explícito: sin él, el compilador sintetiza un deinit "
                        + "AISLADO que en sistemas anteriores al runtime del toolchain pasa por un shim que aborta "
                        + "(docs/repros/isolated-deinit-backdeploy.md). Marca la clase `nonisolated` si no es del actor."
                )
            )
        }
        return out
    }

    // MARK: - R13 — module isolation (PRD-AF-10)

    /// The module a file belongs to, derived from the `Sources/<Target>/…` segment of its
    /// relative path — a target named `MisCasosFeatureCore` (the `--module` split of
    /// `generate-feature`) lives at `Sources/MisCasosFeatureCore/…`, so this returns exactly
    /// that folder name; no extra `Core`/`UI` handling is needed since the generator already
    /// gives the target that literal name. `nil` for a file with no `Sources/` segment
    /// (`Package.swift`, or a file outside any target) — `config.moduleOverride` (`--module`,
    /// set by the build-tool plugin from `sourceModule.name`) takes priority over this and is
    /// authoritative when present, so a nonstandard layout still resolves correctly.
    static func moduleName(relativePath: String) -> String? {
        let components = relativePath.split(separator: "/").map(String.init)
        guard let sourcesIndex = components.firstIndex(of: "Sources"), sourcesIndex + 1 < components.count else {
            return nil
        }
        return components[sourcesIndex + 1]
    }

    private static func checkR13(_ file: ParsedFile, config: ArchLintConfig) -> [Diagnostic] {
        guard !config.modules.isEmpty else { return [] }
        guard let moduleName = config.moduleOverride ?? Self.moduleName(relativePath: file.relativePath) else {
            return []
        }
        guard let rule = config.moduleRule(for: moduleName) else { return [] }

        var out: [Diagnostic] = []
        for ref in file.imports {
            let imported = ref.module
            // `import Testing`/`XCTest` never count — tests are ignored by default already
            // (`ignoreGlobs`), but a fixture/config that re-enables them should not suddenly
            // flag the test framework itself.
            if imported == "Testing" || imported == "XCTest" { continue }

            if rule.forbiddenImports.contains(where: { Glob.matches($0, path: imported) }) {
                out.append(
                    Diagnostic(
                        path: file.path,
                        line: ref.line,
                        col: ref.col,
                        severity: .error,
                        rule: "R13",
                        message: r13Message(module: moduleName, imported: imported)
                    )
                )
                continue
            }
            if !rule.allowedImports.isEmpty, !rule.allowedImports.contains(where: { Glob.matches($0, path: imported) })
            {
                out.append(
                    Diagnostic(
                        path: file.path,
                        line: ref.line,
                        col: ref.col,
                        severity: .error,
                        rule: "R13",
                        message: r13Message(module: moduleName, imported: imported)
                    )
                )
            }
        }
        return out
    }

    /// Two phrasings for the same violation (PRD-AF-10): feature-to-feature — `AGENTS.md`'s
    /// "las features se comunican por Domain y por AppRoute" — vs. reaching straight for an
    /// SDK/Kit instead of the Domain protocol an Adapter/Kit implements.
    private static func r13Message(module: String, imported: String) -> String {
        if imported.hasSuffix("Feature") {
            return
                "'\(module)' no puede importar '\(imported)': las features se comunican por Domain y por AppRoute."
        }
        return
            "'\(module)' no puede importar '\(imported)': entra por un protocolo de Domain implementado en un Adapter/Kit."
    }

    // MARK: - R14 — a dependency pinned to a branch/commit instead of a tag (warning)

    /// Scans `Package.swift`'s own source for `branch:`/`revision:` used as a `.package(...)`
    /// call-argument label (never as a `let`/`var` declaration that happens to share the
    /// name) — lexical, like every other rule here: no PackageDescription parsing, just the
    /// same tokenizer. Called only from the command plugin path (`main.swift`, gated behind
    /// `--check-package-swift`) — a `Package.swift` is never one of a target's `sourceFiles`,
    /// so the build-tool plugin never sees it and never runs this.
    static func checkR14(packageSwiftSource: String, path: String) -> [Diagnostic] {
        let tokens = Lexer.tokenize(packageSwiftSource)
        var out: [Diagnostic] = []
        for (idx, token) in tokens.enumerated()
        where token.kind == .identifier && (token.text == "branch" || token.text == "revision") {
            guard idx + 1 < tokens.count, tokens[idx + 1].kind == .punctuation, tokens[idx + 1].text == ":" else {
                continue
            }
            guard idx > 0, tokens[idx - 1].kind == .punctuation,
                tokens[idx - 1].text == "," || tokens[idx - 1].text == "("
            else { continue }
            out.append(
                Diagnostic(
                    path: path,
                    line: token.line,
                    col: token.col,
                    severity: .warning,
                    rule: "R14",
                    message:
                        "Dependencia por rama/commit ('\(token.text):' en Package.swift): no es reproducible; usa un tag."
                )
            )
        }
        return out
    }

    private static func hasSuffix(_ text: String, _ suffix: String) -> Bool {
        guard !suffix.isEmpty, text.count >= suffix.count else { return false }
        return text.hasSuffix(suffix)
    }
}
