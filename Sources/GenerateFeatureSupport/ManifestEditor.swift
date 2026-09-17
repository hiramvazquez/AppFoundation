import Foundation

/// Pure text edits for a `Package.swift` (or any other text file with the same marker
/// convention): find a pair of `// archinit:<name>-begin` / `// archinit:<name>-end`
/// marker comments (or a single standalone marker comment), insert an entry right before
/// the closing/only marker, reusing that marker line's own leading whitespace as the
/// entry's indentation.
///
/// No Swift parsing, no regex: markers are matched by comparing a line's trimmed content
/// to the marker text verbatim, which is exactly what PRD-AF-10's contract promises —
/// `archinit --multi` writes those markers "en líneas propias" (agent A's job; not built
/// here — see the fixtures in `Scripts/verify-generator.sh`'s "modo multi" block for the
/// exact shape this editor is exercised against).
///
/// String in, string out, no I/O: `Plugins/GenerateFeature/plugin.swift` reads/writes the
/// files, this type only transforms text — which is what makes `ManifestEditorTests.swift`
/// exhaustive without touching a filesystem.
public enum ManifestEditor {
    public enum EditError: Error, CustomStringConvertible, Equatable {
        case markerNotFound(String)

        public var description: String {
            switch self {
            case .markerNotFound(let marker):
                return
                    "No se encontró el marcador '\(marker)' — ¿el manifiesto no está en modo multi, o es de una versión anterior?"
            }
        }
    }

    /// `.inserted(newText)` when the entry was added; `.alreadyPresent` when a matching
    /// entry was already there (idempotent: `text` is returned unmodified by the caller,
    /// this case carries nothing to write).
    public enum InsertResult: Equatable {
        case inserted(String)
        case alreadyPresent
    }

    // MARK: - Single-line marker (`App/AppModule.swift`'s `// archinit:modules`,
    // `App/AppRoute.swift`'s `// archinit:routes`)

    /// Inserts `entry` on its own line right before the line whose trimmed content equals
    /// `marker`. Idempotent: `existingLine` (what an already-registered entry looks like,
    /// e.g. `"LoginModule()"`) is compared against every line in `text` with trailing
    /// commas/whitespace stripped, so `"LoginModule()"` and `"LoginModule(),"` count as
    /// the same entry.
    public static func insertBeforeMarker(
        _ entry: String,
        duplicateOf existingLine: String,
        marker: String,
        in text: String
    ) throws -> InsertResult {
        var lines = text.components(separatedBy: "\n")
        guard let markerIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == marker })
        else {
            throw EditError.markerNotFound(marker)
        }

        let target = normalizedLine(existingLine)
        if lines.contains(where: { normalizedLine($0) == target }) {
            return .alreadyPresent
        }

        let indent = leadingWhitespace(of: lines[markerIndex])
        lines.insert(indented(entry, by: indent), at: markerIndex)
        return .inserted(lines.joined(separator: "\n"))
    }

    /// `insertBeforeMarker` for a marker that closes a comma-separated list (`App/AppModule.swift`'s
    /// array of modules): `element` (without a comma) becomes the list's new last element,
    /// punctuated the way the list already is. If the element above ends in `,` — or there is
    /// none — `element` gets a trailing comma too. If it does not (a formatter configured
    /// without trailing commas removed it), that element gets the comma it now needs as a
    /// separator, and `element` goes without one.
    public static func insertListElementBeforeMarker(
        _ element: String,
        duplicateOf existingLine: String,
        marker: String,
        in text: String
    ) throws -> InsertResult {
        let lines = text.components(separatedBy: "\n")
        guard let markerIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == marker })
        else {
            throw EditError.markerNotFound(marker)
        }
        let previousIndex = lines[..<markerIndex]
            .lastIndex { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty && !trimmed.hasPrefix("//")
            }
        guard let previousIndex else {
            return try insertBeforeMarker("\(element),", duplicateOf: existingLine, marker: marker, in: text)
        }
        let previous = lines[previousIndex]
        let code = previous[..<codeEnd(of: previous)]
        guard let last = code.lastIndex(where: { !$0.isWhitespace }), !",[(".contains(code[last]) else {
            return try insertBeforeMarker("\(element),", duplicateOf: existingLine, marker: marker, in: text)
        }
        let result = try insertBeforeMarker(element, duplicateOf: existingLine, marker: marker, in: text)
        guard case .inserted(let newText) = result else { return result }
        var newLines = newText.components(separatedBy: "\n")
        let afterLast = previous.index(after: last)
        newLines[previousIndex] = String(previous[..<afterLast]) + "," + previous[afterLast...]
        return .inserted(newLines.joined(separator: "\n"))
    }

    // MARK: - Import block (`App/AppModule.swift`'s and `App/RootView.swift`'s `// archinit:imports`)

    /// Adds `import <module>` to the `import` lines right above `marker` (blank lines between
    /// them allowed), before the first one whose module sorts after it — the lexicographic
    /// order `swift format lint`'s `OrderedImports` checks across that whole block. Inserting
    /// right before the marker instead breaks that order whenever the marker sits below the
    /// block. The lines already there are never reordered. With no such lines above the marker,
    /// behaves like `insertBeforeMarker`. Idempotent: an existing `import <module>` line leaves
    /// the text unchanged.
    public static func insertImport(_ module: String, marker: String, in text: String) throws -> InsertResult {
        let importLine = "import \(module)"
        var lines = text.components(separatedBy: "\n")
        guard let markerIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == marker })
        else {
            throw EditError.markerNotFound(marker)
        }
        if lines.contains(where: { normalizedLine($0) == importLine }) {
            return .alreadyPresent
        }

        var blockStart = markerIndex
        while blockStart > 0 {
            let line = lines[blockStart - 1].trimmingCharacters(in: .whitespaces)
            guard line.isEmpty || importedModule(in: line) != nil else { break }
            blockStart -= 1
        }
        let importIndices = (blockStart..<markerIndex).filter { importedModule(in: lines[$0]) != nil }
        guard let lastImport = importIndices.last else {
            return try insertBeforeMarker(importLine, duplicateOf: importLine, marker: marker, in: text)
        }
        let index = importIndices.first { (importedModule(in: lines[$0]) ?? "") > module } ?? lastImport + 1
        lines.insert(leadingWhitespace(of: lines[lastImport]) + importLine, at: index)
        return .inserted(lines.joined(separator: "\n"))
    }

    /// The module of a plain `import Module` line; `nil` for anything else, `@testable` and
    /// declaration imports (`import struct Module.Type`) included.
    private static func importedModule(in line: String) -> String? {
        let parts = line.split(whereSeparator: \.isWhitespace)
        guard parts.count == 2, parts[0] == "import" else { return nil }
        return String(parts[1])
    }
    // MARK: - Marker pair (`Package.swift`'s `targets:`/`products:` archinit blocks)

    /// Inserts `entry` (one or more lines) right before the line whose trimmed content
    /// equals `endMarker`, provided a line matching `beginMarker` appears earlier in
    /// `text`. Idempotent: if `duplicateMarker` already appears as a substring of the
    /// region between the two markers, nothing changes — `.alreadyPresent`. `entry`'s own
    /// internal indentation (relative to its first line) is preserved; the whole block is
    /// then shifted by the end marker's leading whitespace.
    public static func insertBetweenMarkers(
        _ entry: String,
        duplicateMarker: String,
        beginMarker: String,
        endMarker: String,
        in text: String
    ) throws -> InsertResult {
        let lines = text.components(separatedBy: "\n")
        guard let beginIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == beginMarker })
        else {
            throw EditError.markerNotFound(beginMarker)
        }
        guard
            let endIndex = lines[(beginIndex + 1)...]
                .firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == endMarker })
        else {
            throw EditError.markerNotFound(endMarker)
        }

        let region = lines[(beginIndex + 1)..<endIndex].joined(separator: "\n")
        if region.contains(duplicateMarker) {
            return .alreadyPresent
        }

        let indent = leadingWhitespace(of: lines[endIndex])
        var newLines = lines
        newLines.insert(indented(entry, by: indent), at: endIndex)
        return .inserted(newLines.joined(separator: "\n"))
    }

    // MARK: - Reusing an existing plugin declaration

    /// Finds a top-level `.plugin(name: "<name>", …)` literal anywhere in `text` (balanced
    /// parens, naive about parens inside string literals — good enough for the shapes a
    /// `Package.swift` actually contains) and returns it collapsed onto one line, for
    /// reuse verbatim in a newly generated target's `plugins:` array instead of guessing
    /// its `package:` argument — e.g. a project's own `SwiftLintBuildToolPlugin`.
    public static func existingPluginLiteral(named name: String, in text: String) -> String? {
        let nameNeedle = "name: \"\(name)\""
        var searchStart = text.startIndex
        while let pluginStart = text.range(of: ".plugin(", range: searchStart..<text.endIndex) {
            guard let literalEnd = balancedParenEnd(from: pluginStart.lowerBound, in: text) else { return nil }
            let literal = text[pluginStart.lowerBound...literalEnd]
            if literal.contains(nameNeedle) {
                return
                    literal
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .joined(separator: " ")
            }
            searchStart = text.index(after: literalEnd)
        }
        return nil
    }

    /// Given the index of the `(` in something like `.plugin(`, walks forward tracking
    /// paren depth (naive about parens inside string literals — good enough for the
    /// shapes a `Package.swift` actually contains) and returns the index of its matching
    /// closing `)`, or `nil` if the parens never balance.
    private static func balancedParenEnd(from openCallStart: String.Index, in text: String) -> String.Index? {
        var depth = 0
        var sawOpenParen = false
        var index = openCallStart
        while index < text.endIndex {
            let character = text[index]
            if character == "(" {
                depth += 1
                sawOpenParen = true
            } else if character == ")" {
                depth -= 1
                if sawOpenParen, depth == 0 { return index }
            }
            index = text.index(after: index)
        }
        return nil
    }

    // MARK: - Helpers

    private static func normalizedLine(_ line: String) -> String {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix(",") { trimmed.removeLast() }
        return trimmed
    }

    /// Where a line's code ends: before a trailing `//` comment, not counting a `//` inside a
    /// string literal (`"https://…"`).
    private static func codeEnd(of line: String) -> String.Index {
        var inString = false
        var previous: Character?
        for index in line.indices {
            let character = line[index]
            if character == "\"", previous != "\\" {
                inString.toggle()
            } else if character == "/", previous == "/", !inString {
                return line.index(before: index)
            }
            previous = character
        }
        return line.endIndex
    }

    private static func leadingWhitespace(of line: String) -> String {
        String(line.prefix { $0 == " " || $0 == "\t" })
    }

    private static func indented(_ entry: String, by indent: String) -> String {
        entry
            .components(separatedBy: "\n")
            .map { $0.isEmpty ? $0 : indent + $0 }
            .joined(separator: "\n")
    }
}

// MARK: - Composition-root entry for a generated feature module (multi mode)

extension ManifestEditor {
    /// The expression the app's composition root needs to build a generated feature module,
    /// derived from the module's ACTUAL `public init` (the generator renders a different one
    /// per variant): `baseURL:` for `--api`, `throws` when a SwiftData `ModelContainer` is
    /// created for `--local`. Reading the source instead of re-deriving the flags keeps this
    /// truthful when the templates change.
    public static func moduleInitExpression(
        feature: String,
        moduleSource: String,
        baseURLExpression: String
    )
        -> String
    {
        let inits = moduleSource.components(separatedBy: "\n").filter { $0.contains("public init(") }
        let hasBaseURL = inits.contains { $0.contains("baseURL: URL") }
        let isThrowing = inits.contains { $0.contains(") throws") }
        let call = hasBaseURL ? "\(feature)Module(baseURL: \(baseURLExpression))" : "\(feature)Module()"
        return (isThrowing ? "try " : "") + call
    }
}
