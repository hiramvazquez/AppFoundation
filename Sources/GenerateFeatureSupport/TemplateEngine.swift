import Foundation

/// The generator's own template engine (`AGENTS.md`: "sin
/// dependencia de Stencil"). A deliberately small Mustache-like subset: `{{Name}}`
/// substitutions and `{{#flag}}…{{/flag}}` / `{{^flag}}…{{/flag}}` (inverted) sections,
/// nestable. That is everything `AppFoundation/Templates/*.txt` needs — no loops, no
/// partials, no helpers — so the templates stay plain text a human or an agent can read
/// and edit directly, without learning a templating language.
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
        let tags = tokenize(template)
        var index = 0
        let nodes = parse(tags, &index)
        return renderNodes(nodes, substitutions: substitutions, flags: flags)
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
