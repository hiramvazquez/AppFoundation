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
/// 5. `.claude/skills/feature.md` — the `/feature` skill that explains the generator and
///    the lint rules.
///
/// Never overwrites a file that already exists — `archinit` is meant to run once on a
/// fresh project (or safely again on one that already adopted parts of this), never to
/// clobber something a team has since customized.
@main
struct ArchInitPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
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

    private static let archLintYML = """
        # .archlint.yml — configuración de ArchitectureLint.
        # Formato: 'key: value' plano, con listas en bloque ('- item') o inline ('[a, b]').
        # Ver AppFoundation/README.md § Generador y linter para el detalle de cada regla (R1-R11).

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
