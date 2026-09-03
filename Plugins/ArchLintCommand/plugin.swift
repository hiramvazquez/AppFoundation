import Foundation
import PackagePlugin

/// Command plugin: `swift package archlint [--path DIR]`. The same `archlint` executable
/// the build-tool plugin runs, exposed for CI (or a quick manual check) without wiring it
/// into any target — `AGENTS.md`: "El mismo ejecutable se expone
/// como command plugin... para CI sin integrar el build."
///
/// Without `--path`, it scans the whole package directory (respecting `.archlint.yml`'s
/// `ignore:`, which defaults to skipping `Tests/**`; `.build`, `.swiftpm`, `DerivedData`
/// and the VCS directory are skipped always, whatever `ignore:` says — see
/// `ArchLintConfig.alwaysIgnoreGlobs`). `--path DIR` restricts the scan to one
/// subdirectory — handy for a monorepo with several targets.
@main
struct ArchLintCommand: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        var extractor = ArgumentExtractor(arguments)
        let pathOption = extractor.extractOption(named: "path")
        let remaining = extractor.remainingArguments

        let packageDirectory = context.package.directoryURL
        let scanTarget = pathOption.first.map { packageDirectory.appendingPathComponent($0) } ?? packageDirectory

        let archlint = try context.tool(named: "archlint")
        var toolArguments = [scanTarget.path, "--root", packageDirectory.path]

        let configURL = packageDirectory.appendingPathComponent(".archlint.yml")
        if FileManager.default.fileExists(atPath: configURL.path) {
            toolArguments.append(contentsOf: ["--config", configURL.path])
        }
        toolArguments.append(contentsOf: remaining)

        let process = Process()
        process.executableURL = archlint.url
        process.arguments = toolArguments
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            Diagnostics.error("archlint encontró violaciones de arquitectura — ver el detalle arriba.")
            throw ArchLintCommandError.violationsFound
        }
    }
}

enum ArchLintCommandError: Error, CustomStringConvertible {
    case violationsFound

    var description: String {
        "archlint encontró al menos una violación de arquitectura."
    }
}
