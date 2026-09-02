import Foundation

/// A single lexical unit produced by `Lexer.tokenize(_:)`. `archlint` never builds a real
/// AST (no SwiftSyntax, `ARQUITECTURA-KIT-2026-09-02.md` §4): every rule works off this
/// flat token stream, which is enough to find `import` statements, type declarations and
/// identifier references while safely ignoring comments and string contents.
struct Token {
    enum Kind: Equatable {
        /// A Swift identifier or keyword (`class`, `import`, `LoginViewModel`, `init`…).
        case identifier
        /// A single-character operator/punctuation token (`{`, `}`, `(`, `)`, `:`, `,`,
        /// `<`, `>`, `.`, `?`, `!`, `@`, `-`, `>`…). Multi-character operators (`->`, `&&`)
        /// are left as separate single-char tokens — rules that care detect them by
        /// looking at adjacent tokens.
        case punctuation
        /// A `#`-prefixed directive or macro, combined with the identifier that follows it
        /// with no whitespace: `#if`, `#endif`, `#else`, `#elseif`, `#Preview`, `#available`,
        /// `#selector`… A bare `#` with no following letter is emitted as `.punctuation`.
        case poundDirective
        /// An entire string literal (single, multi-line `"""`, or interpolated), collapsed
        /// to one opaque token — rules never look inside a string's contents.
        case stringLiteral
        /// A numeric literal, collapsed to one opaque token.
        case number
    }

    let kind: Kind
    let text: String
    let line: Int
    let col: Int
}

/// Tokenizes Swift source text. Comments (`//`, `/* … */`, nesting supported) are dropped
/// entirely — they never produce tokens. Strings are collapsed to a single opaque token so
/// a rule name or a forbidden identifier mentioned inside a string/comment can never
/// trigger a false positive (`archlint`'s own source is a case in point).
enum Lexer {
    static func tokenize(_ source: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(source)
        var i = 0
        var line = 1
        var col = 1

        func advance() {
            if chars[i] == "\n" {
                line += 1
                col = 1
            } else {
                col += 1
            }
            i += 1
        }

        func peek(_ offset: Int = 0) -> Character? {
            let j = i + offset
            return j < chars.count ? chars[j] : nil
        }

        while i < chars.count {
            let c = chars[i]

            // Whitespace
            if c == " " || c == "\t" || c == "\r" || c == "\n" {
                advance()
                continue
            }

            // Line comment
            if c == "/" && peek(1) == "/" {
                while i < chars.count && chars[i] != "\n" { advance() }
                continue
            }

            // Block comment (nested)
            if c == "/" && peek(1) == "*" {
                var depth = 1
                advance()
                advance()
                while i < chars.count && depth > 0 {
                    if chars[i] == "/" && peek(1) == "*" {
                        depth += 1
                        advance()
                        advance()
                    } else if chars[i] == "*" && peek(1) == "/" {
                        depth -= 1
                        advance()
                        advance()
                    } else {
                        advance()
                    }
                }
                continue
            }

            // Triple-quoted string
            if c == "\"" && peek(1) == "\"" && peek(2) == "\"" {
                let startLine = line
                let startCol = col
                advance()
                advance()
                advance()
                while i < chars.count && !(chars[i] == "\"" && peek(1) == "\"" && peek(2) == "\"") {
                    if chars[i] == "\\" && peek(1) != nil {
                        advance()
                    }
                    advance()
                }
                if i < chars.count {
                    advance()
                    advance()
                    advance()
                }
                tokens.append(Token(kind: .stringLiteral, text: "\"\"\"…\"\"\"", line: startLine, col: startCol))
                continue
            }

            // Single-line string (with escapes and \( … ) interpolation)
            if c == "\"" {
                let startLine = line
                let startCol = col
                advance()
                var interpolationDepth = 0
                while i < chars.count {
                    if chars[i] == "\\" && peek(1) == "(" {
                        interpolationDepth += 1
                        advance()
                        advance()
                        continue
                    }
                    if interpolationDepth > 0 {
                        if chars[i] == "(" { interpolationDepth += 1 }
                        if chars[i] == ")" { interpolationDepth -= 1 }
                        advance()
                        continue
                    }
                    if chars[i] == "\\" && peek(1) != nil {
                        advance()
                        advance()
                        continue
                    }
                    if chars[i] == "\"" {
                        advance()
                        break
                    }
                    if chars[i] == "\n" { break }
                    advance()
                }
                tokens.append(Token(kind: .stringLiteral, text: "\"…\"", line: startLine, col: startCol))
                continue
            }

            // Pound directive / macro
            if c == "#" {
                let startLine = line
                let startCol = col
                var text = "#"
                advance()
                while let ch = peek(), ch.isLetter || ch.isNumber || ch == "_" {
                    text.append(ch)
                    advance()
                }
                if text == "#" {
                    tokens.append(Token(kind: .punctuation, text: "#", line: startLine, col: startCol))
                } else {
                    tokens.append(Token(kind: .poundDirective, text: text, line: startLine, col: startCol))
                }
                continue
            }

            // Identifier / keyword
            if c.isLetter || c == "_" {
                let startLine = line
                let startCol = col
                var text = ""
                while let ch = peek(), ch.isLetter || ch.isNumber || ch == "_" {
                    text.append(ch)
                    advance()
                }
                tokens.append(Token(kind: .identifier, text: text, line: startLine, col: startCol))
                continue
            }

            // Backtick-escaped identifier (`class`, `default` used as a name)
            if c == "`" {
                let startLine = line
                let startCol = col
                advance()
                var text = ""
                while let ch = peek(), ch != "`" {
                    text.append(ch)
                    advance()
                }
                if peek() == "`" { advance() }
                tokens.append(Token(kind: .identifier, text: text, line: startLine, col: startCol))
                continue
            }

            // Number literal
            if c.isNumber {
                let startLine = line
                let startCol = col
                var text = ""
                while let ch = peek(), ch.isNumber || ch == "." || ch == "_" || ch.isLetter {
                    text.append(ch)
                    advance()
                }
                tokens.append(Token(kind: .number, text: text, line: startLine, col: startCol))
                continue
            }

            // Everything else: a single punctuation character.
            let startLine = line
            let startCol = col
            tokens.append(Token(kind: .punctuation, text: String(c), line: startLine, col: startCol))
            advance()
        }

        return tokens
    }
}
