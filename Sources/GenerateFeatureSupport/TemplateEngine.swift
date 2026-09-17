import Foundation

/// The generator's own template engine (`AGENTS.md`: "sin
/// dependencia de Stencil"). A deliberately small Mustache-like subset: `{{Name}}`
/// substitutions and `{{#flag}}…{{/flag}}` / `{{^flag}}…{{/flag}}` (inverted) sections,
/// nestable. That is everything `AppFoundation/Templates/*.txt` needs — no loops, no
/// partials, no helpers — so the templates stay plain text a human or an agent can read
/// and edit directly, without learning a templating language.
///
/// As in Mustache, a line holding nothing but section tags and whitespace is "standalone":
/// the whole line — indentation and newline included — disappears from the output, whether
/// the section renders or not. Without that, every tag line of a template left a blank
/// (or whitespace-only) line behind in the generated code.
public enum TemplateEngine {
    private indirect enum Node {
        case text(String)
        case variable(String)
        case section(name: String, inverted: Bool, children: [Node])
    }

    private enum Tag {
        case text(String)
        case variable(String)
        case sectionOpen(String)
        case sectionInvertedOpen(String)
        case sectionClose(String)
    }

    /// Renders `template`: `substitutions` fill `{{Name}}`/`{{name}}` variables (a missing
    /// key renders as an empty string), `flags` decide which `{{#x}}…{{/x}}`/`{{^x}}…{{/x}}`
    /// sections survive.
    public static func render(_ template: String, substitutions: [String: String], flags: [String: Bool]) -> String {
        let tags = tokenize(removingStandaloneLines(template))
        var index = 0
        let nodes = parse(tags, &index)
        return renderNodes(nodes, substitutions: substitutions, flags: flags)
    }

    // MARK: - Standalone lines

    /// Keeps the tags of every standalone line but drops the line's own whitespace and
    /// newline, so the tags attach to the start of the next line.
    private static func removingStandaloneLines(_ template: String) -> String {
        let lines = template.components(separatedBy: "\n")
        var out = ""
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isOnlySectionTags(trimmed) {
                out += trimmed
            } else {
                out += line
                if index < lines.count - 1 { out += "\n" }
            }
        }
        return out
    }

    private static func isOnlySectionTags(_ text: String) -> Bool {
        var rest = Substring(text)
        guard !rest.isEmpty else { return false }
        while !rest.isEmpty {
            guard rest.hasPrefix("{{"), let close = rest.range(of: "}}"),
                let sigil = rest.dropFirst(2).first, "#^/".contains(sigil)
            else {
                return false
            }
            rest = rest[close.upperBound...]
        }
        return true
    }

    // MARK: - Tokenizing

    private static func tokenize(_ template: String) -> [Tag] {
        var tags: [Tag] = []
        var remainder = Substring(template)

        while let openRange = remainder.range(of: "{{") {
            let before = remainder[remainder.startIndex..<openRange.lowerBound]
            if !before.isEmpty { tags.append(.text(String(before))) }

            guard let closeRange = remainder.range(of: "}}", range: openRange.upperBound..<remainder.endIndex) else {
                // Unterminated tag: treat the rest as plain text.
                tags.append(.text(String(remainder[openRange.lowerBound...])))
                remainder = Substring("")
                break
            }

            let inner = remainder[openRange.upperBound..<closeRange.lowerBound]
            if inner.hasPrefix("#") {
                tags.append(.sectionOpen(String(inner.dropFirst())))
            } else if inner.hasPrefix("^") {
                tags.append(.sectionInvertedOpen(String(inner.dropFirst())))
            } else if inner.hasPrefix("/") {
                tags.append(.sectionClose(String(inner.dropFirst())))
            } else {
                tags.append(.variable(String(inner)))
            }

            remainder = remainder[closeRange.upperBound...]
        }
        if !remainder.isEmpty { tags.append(.text(String(remainder))) }
        return tags
    }

    // MARK: - Parsing (recursive descent; a section's children are parsed until its own
    // matching close tag, so nested — even same-named — sections resolve correctly)

    private static func parse(_ tags: [Tag], _ index: inout Int) -> [Node] {
        var nodes: [Node] = []
        while index < tags.count {
            switch tags[index] {
            case .text(let text):
                nodes.append(.text(text))
                index += 1
            case .variable(let name):
                nodes.append(.variable(name))
                index += 1
            case .sectionOpen(let name):
                index += 1
                let children = parse(tags, &index)
                if index < tags.count, case .sectionClose(name) = tags[index] { index += 1 }
                nodes.append(.section(name: name, inverted: false, children: children))
            case .sectionInvertedOpen(let name):
                index += 1
                let children = parse(tags, &index)
                if index < tags.count, case .sectionClose(name) = tags[index] { index += 1 }
                nodes.append(.section(name: name, inverted: true, children: children))
            case .sectionClose:
                // A close tag with no matching open at this level ends the current block.
                return nodes
            }
        }
        return nodes
    }

    // MARK: - Rendering

    private static func renderNodes(_ nodes: [Node], substitutions: [String: String], flags: [String: Bool]) -> String {
        var out = ""
        for node in nodes {
            switch node {
            case .text(let text):
                out += text
            case .variable(let name):
                out += substitutions[name] ?? ""
            case .section(let name, let inverted, let children):
                let isOn = flags[name] ?? false
                if isOn != inverted {
                    out += renderNodes(children, substitutions: substitutions, flags: flags)
                }
            }
        }
        return out
    }
}

// MARK: - Imports of a rendered Swift file

extension TemplateEngine {
    /// Sorts every run of consecutive `import X` lines, and separately every run of
    /// `@testable import X` lines, by module name — the order `swift format lint`'s
    /// `OrderedImports` requires. A template cannot write that order by hand: some imports
    /// are optional sections, and `import {{CoreModule}}` (multi mode + `--module`) sorts
    /// wherever the feature's own name does.
    public static func sortingImports(in source: String) -> String {
        var lines = source.components(separatedBy: "\n")
        var start = 0
        while start < lines.count {
            guard let prefix = importPrefix(of: lines[start]) else {
                start += 1
                continue
            }
            var end = start + 1
            while end < lines.count, importPrefix(of: lines[end]) == prefix { end += 1 }
            lines[start..<end].sort()
            start = end
        }
        return lines.joined(separator: "\n")
    }

    private static func importPrefix(of line: String) -> String? {
        ["import ", "@testable import "].first { line.hasPrefix($0) }
    }
}
