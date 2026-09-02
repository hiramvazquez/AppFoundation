import Foundation

/// One rule violation, formatted exactly the way Xcode/`swift build` recognize as a
/// navigable diagnostic: `path:line:col: error: [ArchLint.Rn] message`
///.
struct Diagnostic {
    enum Severity: String {
        case error
        case warning
    }

    let path: String
    let line: Int
    let col: Int
    let severity: Severity
    let rule: String
    let message: String

    var formatted: String {
        "\(path):\(line):\(col): \(severity.rawValue): [ArchLint.\(rule)] \(message)"
    }
}
