import Foundation

/// Minimal glob matcher for `.archlint.yml`'s `ignore:` entries. Supports `*` (any run of
/// characters except `/`), `**` (any run of characters including `/`), `?` (one
/// character), and literal path segments — enough for `Tests/**`, `**/Mocks/**`,
/// `**/*Tests.swift`.
enum Glob {
    static func matches(_ pattern: String, path: String) -> Bool {
        let regexPattern = toRegex(pattern)
        guard let regex = try? NSRegularExpression(pattern: regexPattern) else { return false }
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        return regex.firstMatch(in: path, range: range) != nil
    }

    private static func toRegex(_ pattern: String) -> String {
        var result = "^"
        var i = pattern.startIndex
        while i < pattern.endIndex {
            let c = pattern[i]
            if c == "*" {
                let next = pattern.index(after: i)
                if next < pattern.endIndex, pattern[next] == "*" {
                    let afterStars = pattern.index(after: next)
                    if afterStars < pattern.endIndex, pattern[afterStars] == "/" {
                        // "**/" — gitignore/minimatch convention: also matches ZERO leading
                        // path segments, so "**/Tests/**" matches "Tests/Foo.swift" at the
                        // package root, not only "Sub/Tests/Foo.swift". A plain ".*/" would
                        // require at least the "/" to be there, silently under-matching the
                        // single most common case: a top-level Tests/ or Mocks/ directory.
                        result += "(?:.*/)?"
                        i = pattern.index(after: afterStars)
                        continue
                    }
                    result += ".*"
                    i = pattern.index(after: next)
                    continue
                }
                result += "[^/]*"
            } else if c == "?" {
                result += "[^/]"
            } else if ".+()^$|\\{}[]".contains(c) {
                result += "\\\(c)"
            } else {
                result.append(c)
            }
            i = pattern.index(after: i)
        }
        result += "$"
        return result
    }
}
