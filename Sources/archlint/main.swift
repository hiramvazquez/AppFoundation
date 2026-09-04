import Foundation

// `archlint` — the lexical linter behind `AGENTS.md`.
// Zero dependencies, on purpose: it is invoked both as a build-tool plugin (once per
// target, on every build) and as a command plugin (`swift package archlint`, for CI), and
// has to compile and run in a couple of seconds either way.
//
// Usage:
//   archlint <file-or-directory...> [--config PATH] [--root PATH] [--strict]
//
// - Each positional argument is a `.swift` file or a directory to scan recursively.
// - `--config PATH`: explicit `.archlint.yml` to load. Without it, archlint looks for
//   `.archlint.yml` in `--root` (or, lacking that, the first directory argument, or the
//   current directory).
// - `--root PATH`: the directory diagnostics/`ignore:` globs are computed relative to.
//   The build-tool/command plugins always pass this (the target's/package's directory) —
//   SwiftPM plugins cannot set a working directory for the tools they invoke, so relative
//   paths would otherwise depend on an unspecified cwd.
// - `--strict`: same as `.archlint.yml`'s `strict: true`, for a quick one-off run.
// - `--module NAME` (R13): the module every scanned file belongs to — the build-tool plugin
//   passes SwiftPM's `sourceModule.name`. Without it, the module is derived per file from
//   its `Sources/<name>/…` path segment (the command plugin's multi-target scan).
// - `--modules-config PATH` (R13): loads `PATH`'s `modules:` section unconditionally,
//   instead of the local config's own `modules:` (if any) or the default walk-up — see
//   `ArchLintConfig.resolveModules`.
// - `--check-package-swift` (R14): also scans `<root>/Package.swift` for a dependency
//   pinned to a `branch:`/`revision:` instead of a tag. Command plugin only — the build-tool
//   plugin never passes this, since a target's `sourceFiles` never include `Package.swift`.
//
// Exit code: 1 if any `error` diagnostic was emitted, 0 otherwise (warnings — R11's
// `@MainActor` Logic notice, R14's branch/revision notice among them — never fail the build
// on their own).

var arguments = Array(CommandLine.arguments.dropFirst())
var configPathArgument: String?
var rootArgument: String?
var stampArgument: String?
var moduleArgument: String?
var modulesConfigArgument: String?
var forceStrict = false
var checkPackageSwift = false
var positionals: [String] = []

var index = 0
while index < arguments.count {
    let arg = arguments[index]
    switch arg {
    case "--config":
        index += 1
        if index < arguments.count { configPathArgument = arguments[index] }
    case "--root":
        index += 1
        if index < arguments.count { rootArgument = arguments[index] }
    case "--stamp":
        index += 1
        if index < arguments.count { stampArgument = arguments[index] }
    case "--module":
        index += 1
        if index < arguments.count { moduleArgument = arguments[index] }
    case "--modules-config":
        index += 1
        if index < arguments.count { modulesConfigArgument = arguments[index] }
    case "--strict":
        forceStrict = true
    case "--check-package-swift":
        checkPackageSwift = true
    default:
        positionals.append(arg)
    }
    index += 1
}

let fileManager = FileManager.default

func resolvedPath(_ path: String, relativeTo base: String) -> String {
    if path.hasPrefix("/") { return path }
    return (base as NSString).appendingPathComponent(path)
}

let cwd = fileManager.currentDirectoryPath
let root = rootArgument.map { resolvedPath($0, relativeTo: cwd) } ?? cwd

func relativePath(_ absolutePath: String, root: String) -> String {
    let normalizedRoot = root.hasSuffix("/") ? root : root + "/"
    if absolutePath.hasPrefix(normalizedRoot) {
        return String(absolutePath.dropFirst(normalizedRoot.count))
    }
    return absolutePath
}

// MARK: - Config

let configSearchDir: String = {
    if let explicit = configPathArgument {
        return (resolvedPath(explicit, relativeTo: cwd) as NSString).deletingLastPathComponent
    }
    return root
}()

var config: ArchLintConfig
if let explicit = configPathArgument {
    let path = resolvedPath(explicit, relativeTo: cwd)
    if let data = fileManager.contents(atPath: path), let text = String(data: data, encoding: .utf8) {
        config = ArchLintConfig.parse(text)
    } else {
        config = ArchLintConfig()
    }
} else {
    config = ArchLintConfig.load(from: URL(fileURLWithPath: configSearchDir))
}
if forceStrict { config.strict = true }
if let moduleArgument { config.moduleOverride = moduleArgument }

// R13: `modules:` lives in the repo-root `.archlint.yml` in a multi-module repo — see
// `ArchLintConfig.resolveModules` for the search order (local file's own `modules:`, then
// walking up from `root`, then `--modules-config` as an explicit override).
config.modules = ArchLintConfig.resolveModules(
    currentModules: config.modules,
    root: root,
    explicitPath: modulesConfigArgument.map { resolvedPath($0, relativeTo: cwd) }
)

// MARK: - File discovery

func collectSwiftFiles(from path: String) -> [String] {
    // A plain free function (unlike top-level code in this file) is `nonisolated` by
    // default, so it reaches for its own `FileManager.default` rather than the
    // MainActor-isolated top-level `fileManager` let below.
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { return [] }

    if !isDirectory.boolValue {
        return path.hasSuffix(".swift") ? [path] : []
    }

    var results: [String] = []
    guard let enumerator = fileManager.enumerator(atPath: path) else { return [] }
    for case let sub as String in enumerator {
        if sub.hasSuffix(".swift") {
            results.append((path as NSString).appendingPathComponent(sub))
        }
    }
    return results
}

let inputs = positionals.isEmpty ? [root] : positionals.map { resolvedPath($0, relativeTo: cwd) }
var swiftFiles = Set<String>()
for input in inputs {
    for file in collectSwiftFiles(from: input) {
        swiftFiles.insert(file)
    }
}

// `isIgnored` consults the user's `ignore:` AND the fixed `alwaysIgnoreGlobs` (`.build`,
// `.swiftpm`, `DerivedData`, the VCS directory) — a directory scan from the package root
// must never descend into dependency checkouts, whatever the config says.
let candidateFiles = swiftFiles.sorted()
    .filter { path in !config.isIgnored(relativePath: relativePath(path, root: root)) }

// MARK: - Parse + lint

var parsedFiles: [ParsedFile] = []
for path in candidateFiles {
    guard let data = fileManager.contents(atPath: path), let source = String(data: data, encoding: .utf8) else {
        continue
    }
    let rel = relativePath(path, root: root)
    parsedFiles.append(FileParser.parse(path: path, relativePath: rel, source: source))
}

var diagnostics = RuleEngine.run(files: parsedFiles, config: config)

// R14 (command plugin only, see the usage note above `--check-package-swift`): a
// dependency pinned to a branch/commit instead of a tag, read straight from `Package.swift`
// at `--root` — it is never one of `parsedFiles` (not under `Sources/`, and not a target's
// `sourceFiles` either).
if config.isEnabled("R14"), checkPackageSwift {
    let packageSwiftPath = (root as NSString).appendingPathComponent("Package.swift")
    if let data = fileManager.contents(atPath: packageSwiftPath), let source = String(data: data, encoding: .utf8) {
        diagnostics += RuleEngine.checkR14(packageSwiftSource: source, path: packageSwiftPath)
        diagnostics.sort {
            if $0.path != $1.path { return $0.path < $1.path }
            if $0.line != $1.line { return $0.line < $1.line }
            return $0.col < $1.col
        }
    }
}

for diagnostic in diagnostics {
    print(diagnostic.formatted)
}

let errorCount = diagnostics.filter { $0.severity == .error }.count
let warningCount = diagnostics.filter { $0.severity == .warning }.count
if errorCount > 0 {
    FileHandle.standardError.write(
        "archlint: \(errorCount) error(s), \(warningCount) warning(s) in \(parsedFiles.count) file(s).\n"
            .data(using: .utf8)!
    )
    exit(1)
} else {
    FileHandle.standardError.write(
        "archlint: 0 errors, \(warningCount) warning(s) in \(parsedFiles.count) file(s).\n".data(using: .utf8)!
    )
    // `--stamp PATH`: written only on success, so SwiftPM's build-tool plugin has a real
    // output file to track — and so a failed run (exit 1, above) never leaves a stale
    // stamp claiming the target is clean.
    if let stampArgument {
        let stampPath = resolvedPath(stampArgument, relativeTo: cwd)
        try? fileManager.createDirectory(
            atPath: (stampPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        fileManager.createFile(atPath: stampPath, contents: Data("ok\n".utf8))
    }
    exit(0)
}
