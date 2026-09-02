import Foundation

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
    var ignoreGlobs: [String] = [
        "**/Tests/**",
        "**/*Tests.swift",
        "**/*Mock.swift",
        "**/*Mocks.swift",
        "**/*Spy.swift",
        "**/*Stub.swift",
        "**/.build/**",
        "**/.swiftpm/**"
    ]
    var strict = false

    func isEnabled(_ rule: String) -> Bool { !disabledRules.contains(rule) }

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
            break
        }
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
