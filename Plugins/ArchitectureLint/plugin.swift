import Foundation
import PackagePlugin

/// Build-tool plugin: attach it to a target and every `swift build`/Xcode build runs
/// `archlint` over that target's `sourceFiles` before compiling — an architecture
/// violation fails the build with a navigable diagnostic
///.
///
/// ```swift
/// .target(
///     name: "MyApp",
///     dependencies: [...],
///     plugins: [.plugin(name: "ArchitectureLint", package: "AppFoundation")]
/// )
/// ```
///
/// In Xcode: select the project → the target → Build Phases → **Run Build Tool
/// Plug-ins** → **+** → `ArchitectureLint`.
@main
struct ArchitectureLint: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let sourceModule = target as? SourceModuleTarget else { return [] }

        let swiftFiles = sourceModule.sourceFiles.filter { $0.url.pathExtension == "swift" }.map(\.url)
        guard !swiftFiles.isEmpty else { return [] }

        let archlint = try context.tool(named: "archlint")
        let packageDirectory = context.package.directoryURL

        var arguments = swiftFiles.map(\.path)
        arguments.append(contentsOf: ["--root", packageDirectory.path])
        // R13 (PRD-AF-10): pass SwiftPM's own module name — authoritative over deriving it
        // from each file's `Sources/<name>/…` path, which is what the command plugin falls
        // back to when it scans several targets in one run.
        arguments.append(contentsOf: ["--module", sourceModule.name])

        let configURL = packageDirectory.appendingPathComponent(".archlint.yml")
        if FileManager.default.fileExists(atPath: configURL.path) {
            arguments.append(contentsOf: ["--config", configURL.path])
        }

        let stampURL = context.pluginWorkDirectoryURL.appendingPathComponent("\(sourceModule.name)-archlint.stamp")
        arguments.append(contentsOf: ["--stamp", stampURL.path])

        return [
            .buildCommand(
                displayName: "ArchitectureLint: \(sourceModule.name)",
                executable: archlint.url,
                arguments: arguments,
                inputFiles: swiftFiles,
                outputFiles: [stampURL]
            )
        ]
    }
}
