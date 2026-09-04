import Foundation

/// One module's import policy from a `modules:` section (R13): `pattern` matches a module
/// name either literally or as a glob (`*Feature`, `Firebase*`) — see
/// `ArchLintConfig.moduleRule(for:)` for the matching order.
struct ModuleRule: Equatable {
    let pattern: String
    var allowedImports: [String] = []
    var forbiddenImports: [String] = []
}

/// `.archlint.yml` configuration, read from the target/package root. `archlint` ships its
/// own minimal reader — a subset of YAML that covers exactly the shapes this file needs
/// (`AGENTS.md`: "sin SwiftSyntax en la v1", same philosophy
/// applies to the config format: no YAML library dependency).
///
/// ## Supported syntax
///
/// ```yaml
/// # Comments start with '#' and run to end of line.
/// strict: true                      # scalar: true/false/yes/no/1/0 (case-insensitive)
/// suffixes.viewModel: ViewModel     # dotted keys instead of nested maps
/// suffixes.logic: Logic
/// suffixes.service: Service
/// suffixes.store: Store
/// disabled: [R9, R11]               # inline list …
/// ignore:                           # … or a block list, one '- item' per line
///   - Generated/**
///   - "**/Legacy/**"
/// ```
///
/// Anything else (nested maps, anchors, multi-line scalars…) is out of scope — this is
/// deliberately the "flat `key: value`" format the PRD allows as a fallback, extended only
/// with block/inline lists because `ignore:`/`disabled:` need them.
struct ArchLintConfig {
    var viewModelSuffix = "ViewModel"
    var logicSuffix = "Logic"
    var serviceSuffix = "Service"
    var storeSuffix = "Store"
    var moduleSuffix = "Module"
    var disabledRules: Set<String> = []
    /// The user-facing ignore list. These are the defaults; a file that sets `ignore:`
    /// REPLACES them (see `parse`). Build products and dependency checkouts are not in
    /// here on purpose — they live in `alwaysIgnoreGlobs`, which no `ignore:` can drop.
    var ignoreGlobs: [String] = [
        "**/Tests/**",
        "**/*Tests.swift",
        "**/*Mock.swift",
        "**/*Mocks.swift",
        "**/*Spy.swift",
        "**/*Stub.swift"
    ]
    var strict = false

    /// R13 (PRD-AF-10): per-module import policy, from a `modules:` section — either the
    /// repo-root `.archlint.yml` (see `resolveModules`) or, in a single-package repo, this
    /// same file. Empty (the default) means R13 does nothing — full backward compatibility
    /// for a package that never adopted the multi-module layout.
    var modules: [ModuleRule] = []

    /// Set only via `--module <name>`: the build-tool plugin passes SwiftPM's own
    /// `sourceModule.name`, authoritative over deriving the module from the file's
    /// `Sources/<name>/…` path (`RuleEngine.moduleName(relativePath:)`) — a target with a
    /// nonstandard source layout still gets the right module.
    var moduleOverride: String?

    /// Globs applied on EVERY run, before and regardless of `ignoreGlobs`: SwiftPM's build
    /// directory (`.build/checkouts` holds every dependency's sources — AppFoundation's own
    /// "bad" lint fixtures among them), `.swiftpm`, Xcode's `DerivedData` and the VCS
    /// directory. Kept apart from `ignoreGlobs` because an explicit `ignore:` replaces that
    /// list, and when `.build`/`.swiftpm` lived there a consumer whose `.archlint.yml`
    /// listed anything at all (the one `archinit` writes does) silently lost them — so
    /// `swift package archlint` without `--path` walked into `.build/checkouts` and failed
    /// on someone else's code (PRD-X-05, A1).
    static let alwaysIgnoreGlobs: [String] = [
        "**/.build/**",
        "**/.swiftpm/**",
        "**/DerivedData/**",
        "**/.git/**"
    ]

    func isEnabled(_ rule: String) -> Bool { !disabledRules.contains(rule) }

    /// R13: the rule that applies to `moduleName`, if any. Matching order: first an EXACT
    /// literal match (whatever position it has in `modules:` — a specific module name always
    /// wins over a glob that also happens to match it), then the first glob match in the
    /// order `modules:` declared them (`*Feature`, `Firebase*`…).
    func moduleRule(for moduleName: String) -> ModuleRule? {
        if let exact = modules.first(where: { $0.pattern == moduleName }) { return exact }
        for rule in modules where rule.pattern != moduleName {
            if Glob.matches(rule.pattern, path: moduleName) { return rule }
        }
        return nil
    }

    /// Accumulates one `allowedImports`/`forbiddenImports` entry for `pattern` — used by the
    /// flat `modules.<glob>.allowedImports: [...]` form (see `apply(key:listItem:...)`
    /// below); the nested `modules:` block form is parsed separately by
    /// `parseModulesSection`.
    mutating func addModuleImport(pattern: String, allowed: String? = nil, forbidden: String? = nil) {
        if let idx = modules.firstIndex(where: { $0.pattern == pattern }) {
            if let allowed { modules[idx].allowedImports.append(allowed) }
            if let forbidden { modules[idx].forbiddenImports.append(forbidden) }
        } else {
            var rule = ModuleRule(pattern: pattern)
            if let allowed { rule.allowedImports.append(allowed) }
            if let forbidden { rule.forbiddenImports.append(forbidden) }
            modules.append(rule)
        }
    }

    /// R13's config resolution: today's per-target `.archlint.yml` covers layer rules
    /// (R1-R12); in a multi-module repo, `modules:` lives instead in the REPO ROOT's
    /// `.archlint.yml`, above the package. `self.modules` — already loaded from the local
    /// file passed to `parse`/`load` — wins if it is non-empty (the local file already IS
    /// the root, or was told to be via `--config`); otherwise this walks up from `root`
    /// through each parent directory looking for a `.archlint.yml` with a non-empty
    /// `modules:` section, merging ONLY that section, and stops at the first one found.
    /// `explicitPath` (`--modules-config PATH`) skips all of that and loads that file's
    /// `modules:` unconditionally.
    static func resolveModules(
        currentModules: [ModuleRule],
        root: String,
        explicitPath: String?,
        fileManager: FileManager = .default
    ) -> [ModuleRule] {
        if let explicitPath {
            guard let data = fileManager.contents(atPath: explicitPath),
                let text = String(data: data, encoding: .utf8)
            else { return currentModules }
            return ArchLintConfig.parse(text).modules
        }

        guard currentModules.isEmpty else { return currentModules }

        var dir = root
        var guardCount = 0
        while !dir.isEmpty, guardCount < 64 {
            let candidate = (dir as NSString).appendingPathComponent(".archlint.yml")
            if let data = fileManager.contents(atPath: candidate),
                let text = String(data: data, encoding: .utf8)
            {
                let parsed = ArchLintConfig.parse(text)
                if !parsed.modules.isEmpty { return parsed.modules }
            }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir || parent.isEmpty { break }
            dir = parent
            guardCount += 1
        }
        return currentModules
    }

    /// Whether `relativePath` (relative to `--root`, or absolute when the file lives
    /// outside it) is excluded from analysis: matched by `alwaysIgnoreGlobs` or by the
    /// (default or user-provided) `ignoreGlobs`.
    func isIgnored(relativePath: String) -> Bool {
        Self.alwaysIgnoreGlobs.contains { Glob.matches($0, path: relativePath) }
            || ignoreGlobs.contains { Glob.matches($0, path: relativePath) }
    }

    static let empty = ArchLintConfig()

    /// Loads `.archlint.yml` from `directory`, if present. Returns the default
    /// configuration (with the built-in ignore list above) when there is no file — a
    /// project with no config still gets sane defaults, notably ignoring `Tests/`.
    static func load(from directory: URL) -> ArchLintConfig {
        let url = directory.appendingPathComponent(".archlint.yml")
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            return ArchLintConfig()
        }
        return parse(text)
    }

    static func parse(_ text: String) -> ArchLintConfig {
        var config = ArchLintConfig()
        // A file that sets `ignore:` explicitly replaces the built-in defaults rather than
        // appending to them — otherwise there would be no way to un-ignore `Tests/**`.
        // `alwaysIgnoreGlobs` is untouched by this: it is not part of `ignoreGlobs`.
        var ignoreExplicit = false

        var pendingListKey: String?
        let lines = text.components(separatedBy: .newlines)

        for rawLine in lines {
            let line = stripComment(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Block-list item: "- value" (must be indented under a "key:" line with no
            // inline value).
            if trimmed.hasPrefix("- ") || trimmed == "-" {
                guard let key = pendingListKey else { continue }
                let value = unquote(String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces))
                apply(key: key, listItem: value, to: &config, ignoreExplicit: &ignoreExplicit)
                continue
            }

            guard let colonIndex = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[trimmed.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

            if rawValue.isEmpty {
                // Expect a following block list.
                pendingListKey = key
                continue
            }
            pendingListKey = nil

            if rawValue.hasPrefix("[") && rawValue.hasSuffix("]") {
                let inner = String(rawValue.dropFirst().dropLast())
                let items = inner.split(separator: ",").map { unquote($0.trimmingCharacters(in: .whitespaces)) }
                for item in items where !item.isEmpty {
                    apply(key: key, listItem: item, to: &config, ignoreExplicit: &ignoreExplicit)
                }
                continue
            }

            apply(key: key, scalar: unquote(rawValue), to: &config)
        }

        // The nested `modules:` block form (two levels: module pattern, then its
        // `allowedImports:`/`forbiddenImports:` lists) needs real indentation, which the
        // flat loop above discards on purpose — parsed separately, then merged in. The flat
        // `modules.<glob>.allowedImports: [...]` form above already fed `config.modules`
        // directly via `apply(key:listItem:...)`, so a file using only that form leaves this
        // call a no-op (no top-level "modules:" line for it to find).
        config.modules.append(contentsOf: parseModulesSection(lines: lines))

        return config
    }

    private static func apply(key: String, scalar rawValue: String, to config: inout ArchLintConfig) {
        switch key {
        case "strict":
            config.strict = isTruthy(rawValue)
        case "suffixes.viewModel": config.viewModelSuffix = rawValue
        case "suffixes.logic": config.logicSuffix = rawValue
        case "suffixes.service": config.serviceSuffix = rawValue
        case "suffixes.store": config.storeSuffix = rawValue
        case "suffixes.module": config.moduleSuffix = rawValue
        case "disabled":
            config.disabledRules.formUnion(splitList(rawValue))
        default:
            break
        }
    }

    private static func apply(
        key: String,
        listItem: String,
        to config: inout ArchLintConfig,
        ignoreExplicit: inout Bool
    ) {
        switch key {
        case "ignore":
            if !ignoreExplicit {
                config.ignoreGlobs = []
                ignoreExplicit = true
            }
            config.ignoreGlobs.append(listItem)
        case "disabled":
            config.disabledRules.insert(listItem)
        default:
            // The flat form of R13's module import lists: `modules.<glob>.allowedImports:
            // [...]` / `modules.<glob>.forbiddenImports: [...]`, block or inline — both
            // shapes reach here as one `listItem` call per entry. The nested `modules:`
            // block form (documented as the primary shape) is parsed separately, by
            // `parseModulesSection`, since it needs real indentation.
            if key.hasPrefix("modules.") {
                let rest = String(key.dropFirst("modules.".count))
                if rest.hasSuffix(".allowedImports") {
                    let pattern = unquote(String(rest.dropLast(".allowedImports".count)))
                    config.addModuleImport(pattern: pattern, allowed: listItem)
                } else if rest.hasSuffix(".forbiddenImports") {
                    let pattern = unquote(String(rest.dropLast(".forbiddenImports".count)))
                    config.addModuleImport(pattern: pattern, forbidden: listItem)
                }
            }
        }
    }

    /// Parses the NESTED `modules:` block — two levels of indentation, module pattern then
    /// its `allowedImports:`/`forbiddenImports:` lists — which the flat line-by-line loop in
    /// `parse(_:)` above cannot express (it discards indentation on purpose, working only
    /// off `key: value`/`- item` shapes). Independent from that loop: it re-scans the same
    /// `lines`, ignoring everything outside a top-level `modules:` line. A file with no such
    /// line returns `[]`.
    ///
    /// ```yaml
    /// modules:
    ///   Domain:
    ///     allowedImports: [Foundation]
    ///   "*Feature":
    ///     allowedImports: [Foundation, SwiftUI, Domain]
    ///     forbiddenImports: ["*Feature", "Firebase*"]
    /// ```
    private static func parseModulesSection(lines: [String]) -> [ModuleRule] {
        var modules: [ModuleRule] = []

        var i = 0
        while i < lines.count {
            let raw = stripComment(lines[i])
            if indent(of: raw) == 0, raw.trimmingCharacters(in: .whitespaces) == "modules:" {
                i += 1
                break
            }
            i += 1
        }
        guard i <= lines.count else { return modules }

        var patternIndent: Int?
        var currentPattern: String?
        var currentAllowed: [String] = []
        var currentForbidden: [String] = []
        var pendingListKey: String?

        func flushCurrent() {
            if let pattern = currentPattern {
                modules.append(
                    ModuleRule(pattern: pattern, allowedImports: currentAllowed, forbiddenImports: currentForbidden)
                )
            }
            currentPattern = nil
            currentAllowed = []
            currentForbidden = []
            pendingListKey = nil
        }

        while i < lines.count {
            let raw = stripComment(lines[i])
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                i += 1
                continue
            }
            let lineIndent = indent(of: raw)

            if trimmed.hasPrefix("- ") || trimmed == "-" {
                if let key = pendingListKey {
                    let value = unquote(String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces))
                    if key == "allowedImports" { currentAllowed.append(value) }
                    if key == "forbiddenImports" { currentForbidden.append(value) }
                }
                i += 1
                continue
            }

            if lineIndent == 0 {
                // Back to a top-level key: the `modules:` block is over.
                break
            }
            guard let colonIndex = trimmed.firstIndex(of: ":") else {
                i += 1
                continue
            }
            let key = unquote(String(trimmed[trimmed.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces))
            let rawValue = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

            if patternIndent == nil { patternIndent = lineIndent }

            if lineIndent == patternIndent {
                // A new module pattern entry: flush whatever the previous one accumulated.
                flushCurrent()
                currentPattern = key
            } else if key == "allowedImports" || key == "forbiddenImports" {
                if rawValue.isEmpty {
                    pendingListKey = key
                } else if rawValue.hasPrefix("[") && rawValue.hasSuffix("]") {
                    let inner = String(rawValue.dropFirst().dropLast())
                    let items = inner.split(separator: ",").map { unquote($0.trimmingCharacters(in: .whitespaces)) }
                        .filter { !$0.isEmpty }
                    if key == "allowedImports" { currentAllowed.append(contentsOf: items) }
                    if key == "forbiddenImports" { currentForbidden.append(contentsOf: items) }
                    pendingListKey = nil
                }
            }
            i += 1
        }
        flushCurrent()
        return modules
    }

    /// Count of leading space/tab characters — `parseModulesSection`'s only use of
    /// indentation; every other shape in this file works off trimmed lines.
    private static func indent(of line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.count
    }

    private static func splitList(_ value: String) -> [String] {
        value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func isTruthy(_ value: String) -> Bool {
        ["true", "yes", "1", "on"].contains(value.lowercased())
    }

    private static func unquote(_ value: String) -> String {
        var v = value
        if (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")), v.count >= 2 {
            v = String(v.dropFirst().dropLast())
        }
        return v
    }

    private static func stripComment(_ line: String) -> String {
        // A '#' inside quotes would be misread as a comment start — none of our expected
        // values need one, so this stays a straightforward scan.
        var inQuotes: Character?
        for (index, ch) in line.enumerated() {
            if let q = inQuotes {
                if ch == q { inQuotes = nil }
                continue
            }
            if ch == "\"" || ch == "'" {
                inQuotes = ch
                continue
            }
            if ch == "#" {
                return String(line.prefix(index))
            }
        }
        return line
    }
}
