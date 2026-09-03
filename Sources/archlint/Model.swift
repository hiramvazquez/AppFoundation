import Foundation

/// An `import` statement found in a file.
struct ImportRef {
    let module: String
    let line: Int
    let col: Int
}

/// A `class`/`struct`/`enum`/`actor`/`protocol` declaration. Only what the rules need:
/// the keyword, the name, the raw inheritance-clause tokens (never split by comma — a
/// generic like `LogicViewModel<any LoginLogicProtocol>` would break a naive split), and
/// any attributes (`@MainActor`, `@ModelActor`…) directly preceding it.
struct TypeDecl {
    let keyword: String
    let name: String
    let inheritanceTokens: [String]
    let attributes: [String]
    let line: Int
    let col: Int

    func inherits(_ name: String) -> Bool {
        inheritanceTokens.contains(name)
    }
}

/// A single `init(...)` declaration's parameter, reduced to its type text — the only part
/// R6 ("no concrete Service/Store/Logic type in another layer's `init`") needs.
struct InitParam {
    let typeText: String
    let line: Int
    let col: Int
}

struct InitDecl {
    let params: [InitParam]
    let line: Int
    let col: Int
}

/// A `let`/`var name: Type` stored-property-shaped declaration (R12: `let`/`var viewModel:`
/// in a View). Lexical, like every other shape here: it also matches a typed local
/// (`let x: Int = 1` inside a function), which is an accepted over-approximation for a
/// warning-severity rule — the same trade-off R11 makes for `@MainActor`.
struct PropertyDecl {
    let name: String
    /// Whether an `@State` attribute appears on the same line as `let`/`var`, or on the
    /// line directly above it — the two shapes `archinit`-generated code and hand-written
    /// code both use (`@State private var x: T` on one line, or `@State` alone above `var
    /// x: T`).
    let hasNearbyStateAttribute: Bool
    let line: Int
    let col: Int
}

/// An identifier token reference, kept separate from `Token` so rule code doesn't need to
/// know about punctuation/strings/comments — only "this identifier appears here, and it
/// isn't inside a `#if DEBUG`/`#Preview` exempt region."
struct IdentifierRef {
    let name: String
    let line: Int
    let col: Int
}

/// One source file, fully tokenized and pre-scanned for the handful of shapes every rule
/// needs (imports, type declarations, `init` parameter types, identifier references
/// outside preview/debug scaffolding).
struct ParsedFile {
    let path: String
    let relativePath: String
    let imports: [ImportRef]
    let importedModules: Set<String>
    let typeDecls: [TypeDecl]
    let inits: [InitDecl]
    /// Every identifier reference in the file that is NOT inside a `#if` condition
    /// containing `DEBUG`, and NOT inside a `#Preview { … }` body — preview/debug
    /// scaffolding routinely wires a real (non-mock) stack for convenience and is exempt
    /// from the layering rules, the same way it's exempt from shipping in a release build.
    let references: [IdentifierRef]
    /// Every `let`/`var name: Type` declaration in the file (R12).
    let properties: [PropertyDecl]
}

enum FileParser {
    static func parse(path: String, relativePath: String, source: String) -> ParsedFile {
        let tokens = Lexer.tokenize(source)
        var imports: [ImportRef] = []
        var typeDecls: [TypeDecl] = []
        var inits: [InitDecl] = []
        var references: [IdentifierRef] = []
        var properties: [PropertyDecl] = []

        let exemptRanges = Self.exemptRanges(tokens: tokens)
        func isExempt(_ index: Int) -> Bool {
            exemptRanges.contains { $0.contains(index) }
        }

        // Every line an `@State` attribute appears on (R12) — computed once up front so the
        // property scan below can just ask "is @State on this line, or the one above?"
        // without walking backward through modifiers/attributes token by token.
        var stateAttributeLines: Set<Int> = []
        for (idx, t) in tokens.enumerated()
        where t.kind == .identifier && t.text == "State" && idx > 0 && tokens[idx - 1].kind == .punctuation
            && tokens[idx - 1].text == "@"
        {
            stateAttributeLines.insert(t.line)
        }

        let typeKeywords: Set<String> = ["class", "struct", "enum", "actor", "protocol"]
        // Deliberately excludes "class": it is a type-declaration keyword AND a member
        // modifier (`class func`/`class var`) — the type-declaration scan below tells the
        // two apart itself (a modifier's "class" is followed by `func`/`var`/`let`, never
        // by the type's name), so folding it into this "skip, this isn't a declaration"
        // list would blind the scanner to every `class` declaration in the file.
        let modifierKeywords: Set<String> = [
            "public", "private", "fileprivate", "internal", "open", "final", "nonisolated",
            "indirect", "required", "convenience", "static", "override", "mutating",
            "package", "distributed"
        ]
        let memberIntroducers: Set<String> = ["func", "var", "let", "subscript"]

        var i = 0
        while i < tokens.count {
            let token = tokens[i]

            if token.kind == .identifier {
                if !isExempt(i) {
                    references.append(IdentifierRef(name: token.text, line: token.line, col: token.col))
                }

                // import Foo[.Bar…]
                if token.text == "import" {
                    var j = i + 1
                    // Skip a submodule-kind marker: `import struct Foo.Bar`.
                    if j < tokens.count, tokens[j].kind == .identifier,
                        ["struct", "class", "enum", "protocol", "func", "var", "typealias"].contains(tokens[j].text)
                    {
                        j += 1
                    }
                    if j < tokens.count, tokens[j].kind == .identifier {
                        imports.append(ImportRef(module: tokens[j].text, line: token.line, col: token.col))
                    }
                }

                // Type declaration: `class/struct/enum/actor/protocol Name[<...>][: A, B] {`
                // (or, for a protocol, no body at all in a fixture — still fine since we
                // only read up to `{`/end of tokens).
                if typeKeywords.contains(token.text) {
                    let prevIsDot = i > 0 && tokens[i - 1].kind == .punctuation && tokens[i - 1].text == "."
                    let nextIsMemberIntroducer = i + 1 < tokens.count && memberIntroducers.contains(tokens[i + 1].text)
                    if !prevIsDot, !nextIsMemberIntroducer, i + 1 < tokens.count, tokens[i + 1].kind == .identifier {
                        let name = tokens[i + 1].text
                        var k = i + 2
                        // Generic parameter clause: <...>
                        if k < tokens.count, tokens[k].text == "<" {
                            var depth = 1
                            k += 1
                            while k < tokens.count, depth > 0 {
                                if tokens[k].text == "<" { depth += 1 }
                                if tokens[k].text == ">" { depth -= 1 }
                                k += 1
                            }
                        }
                        var inheritance: [String] = []
                        if k < tokens.count, tokens[k].text == ":" {
                            k += 1
                            var depth = 0
                            while k < tokens.count {
                                let t = tokens[k].text
                                if depth == 0 && (t == "{" || t == "where") { break }
                                if t == "<" || t == "(" || t == "[" { depth += 1 }
                                if t == ">" || t == ")" || t == "]" { depth = max(0, depth - 1) }
                                if tokens[k].kind == .identifier { inheritance.append(t) }
                                k += 1
                            }
                        }
                        // Attributes directly preceding the declaration (walk back over
                        // modifiers and `@Attr` pairs).
                        var attributes: [String] = []
                        var b = i - 1
                        while b >= 0 {
                            let t = tokens[b]
                            if t.kind == .identifier && modifierKeywords.contains(t.text) {
                                b -= 1
                                continue
                            }
                            if t.kind == .identifier, b > 0, tokens[b - 1].kind == .punctuation,
                                tokens[b - 1].text == "@"
                            {
                                attributes.append(t.text)
                                b -= 2
                                continue
                            }
                            break
                        }
                        typeDecls.append(
                            TypeDecl(
                                keyword: token.text,
                                name: name,
                                inheritanceTokens: inheritance,
                                attributes: attributes,
                                line: token.line,
                                col: token.col
                            )
                        )
                    }
                }

                // `init` declaration: `init[?][!](params) [throws] [-> X] {`  — never a call
                // (a call would be `Type.init(...)`, preceded by `.`).
                if token.text == "init" {
                    let prevIsDot = i > 0 && tokens[i - 1].kind == .punctuation && tokens[i - 1].text == "."
                    var k = i + 1
                    if k < tokens.count, tokens[k].kind == .punctuation, tokens[k].text == "?" || tokens[k].text == "!"
                    {
                        k += 1
                    }
                    if !prevIsDot, k < tokens.count, tokens[k].kind == .punctuation, tokens[k].text == "(" {
                        let (params, endIndex) = Self.parseParams(tokens: tokens, openParenIndex: k)
                        inits.append(InitDecl(params: params, line: token.line, col: token.col))
                        i = endIndex
                        continue
                    }
                }

                // Property-shaped declaration: `let`/`var name: …` — a typed local
                // (`let x: Int = 1` inside a function) matches too, and is an accepted
                // over-approximation (R12 is a warning, never an error).
                if token.text == "let" || token.text == "var" {
                    if i + 2 < tokens.count, tokens[i + 1].kind == .identifier,
                        tokens[i + 2].kind == .punctuation, tokens[i + 2].text == ":"
                    {
                        let nameToken = tokens[i + 1]
                        let hasNearbyState =
                            stateAttributeLines.contains(token.line) || stateAttributeLines.contains(token.line - 1)
                        properties.append(
                            PropertyDecl(
                                name: nameToken.text,
                                hasNearbyStateAttribute: hasNearbyState,
                                line: token.line,
                                col: token.col
                            )
                        )
                    }
                }
            }

            i += 1
        }

        return ParsedFile(
            path: path,
            relativePath: relativePath,
            imports: imports,
            importedModules: Set(imports.map(\.module)),
            typeDecls: typeDecls,
            inits: inits,
            references: references,
            properties: properties
        )
    }

    /// Splits a parenthesized parameter list into top-level parameters, taking the type
    /// text as everything after the parameter's LAST top-level `:` up to its `=` (default
    /// value) or the end of the parameter.
    private static func parseParams(tokens: [Token], openParenIndex: Int) -> ([InitParam], Int) {
        var depth = 0
        var i = openParenIndex
        var current: [Token] = []
        var params: [InitParam] = []

        func flush() {
            guard !current.isEmpty else { return }
            var lastColon: Int?
            var localDepth = 0
            for (idx, t) in current.enumerated() {
                if t.text == "<" || t.text == "(" || t.text == "[" { localDepth += 1 }
                if t.text == ">" || t.text == ")" || t.text == "]" { localDepth -= 1 }
                if localDepth == 0 && t.text == ":" { lastColon = idx }
            }
            guard let colonIndex = lastColon else { return }
            var typeTokens = Array(current[(colonIndex + 1)...])
            // Drop a trailing default value: `= …`.
            var eqDepth = 0
            if let eqIndex = typeTokens.firstIndex(where: { t in
                if t.text == "<" || t.text == "(" || t.text == "[" { eqDepth += 1 }
                if t.text == ">" || t.text == ")" || t.text == "]" { eqDepth -= 1 }
                return eqDepth == 0 && t.text == "="
            }) {
                typeTokens = Array(typeTokens[..<eqIndex])
            }
            guard let first = typeTokens.first else { return }
            let text = typeTokens.map(\.text).joined(separator: " ")
            params.append(InitParam(typeText: text, line: first.line, col: first.col))
        }

        // Move past the opening "(".
        depth = 1
        i = openParenIndex + 1
        while i < tokens.count, depth > 0 {
            let t = tokens[i]
            if t.text == "(" || t.text == "[" || t.text == "<" { depth += 1 }
            if t.text == ")" || t.text == "]" || t.text == ">" {
                depth -= 1
                if depth == 0 { break }
            }
            if depth == 1 && t.text == "," {
                flush()
                current = []
                i += 1
                continue
            }
            current.append(t)
            i += 1
        }
        flush()
        return (params, i + 1)
    }

    /// Token-index ranges exempt from reference scanning: inside a `#if <cond containing
    /// DEBUG> … #endif` block, or inside a `#Preview { … }` body. Both are preview/debug
    /// scaffolding that never ships (`AGENTS.md`'s examples wire a
    /// real stack — not a mock — into their `#Preview`, e.g. `LoginApp`'s `LoginPreview`).
    private static func exemptRanges(tokens: [Token]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var ifStack: [(startIndex: Int, isDebug: Bool)] = []
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            if t.kind == .poundDirective {
                if t.text == "#if" || t.text == "#elseif" {
                    // Condition tokens: rest of the same source line.
                    var j = i + 1
                    var isDebug = false
                    while j < tokens.count, tokens[j].line == t.line {
                        if tokens[j].kind == .identifier, tokens[j].text == "DEBUG" { isDebug = true }
                        j += 1
                    }
                    ifStack.append((i, isDebug))
                } else if t.text == "#endif" {
                    if let top = ifStack.popLast(), top.isDebug {
                        ranges.append(top.startIndex..<(i + 1))
                    }
                } else if t.text == "#Preview" {
                    var j = i + 1
                    // Optional argument list: #Preview("Title") { … }
                    if j < tokens.count, tokens[j].text == "(" {
                        var depth = 1
                        j += 1
                        while j < tokens.count, depth > 0 {
                            if tokens[j].text == "(" { depth += 1 }
                            if tokens[j].text == ")" { depth -= 1 }
                            j += 1
                        }
                    }
                    if j < tokens.count, tokens[j].text == "{" {
                        var depth = 1
                        let start = i
                        j += 1
                        while j < tokens.count, depth > 0 {
                            if tokens[j].text == "{" { depth += 1 }
                            if tokens[j].text == "}" { depth -= 1 }
                            j += 1
                        }
                        ranges.append(start..<j)
                        i = j
                        continue
                    }
                }
            }
            i += 1
        }
        return ranges
    }
}
