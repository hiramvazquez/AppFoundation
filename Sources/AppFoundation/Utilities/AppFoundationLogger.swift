import Foundation

/// Lightweight debug logging helpers used internally by AppFoundation.
///
/// The package intentionally stays dependency-free. In DEBUG builds these
/// helpers print readable messages; in RELEASE builds they become no-ops.
enum AppFoundationLogger {
    static func debug(_ message: @autoclosure () -> String, category: String) {
        #if DEBUG
        print("[DEBUG][\(category)] \(message())")
        #endif
    }

    static func info(_ message: @autoclosure () -> String, category: String) {
        #if DEBUG
        print("[INFO][\(category)] \(message())")
        #endif
    }

    static func warning(_ message: @autoclosure () -> String, category: String) {
        #if DEBUG
        print("[WARN][\(category)] \(message())")
        #endif
    }

    static func error(_ message: @autoclosure () -> String, category: String) {
        #if DEBUG
        print("[ERROR][\(category)] \(message())")
        #endif
    }
}

@inline(__always) func logDebug(_ message: @autoclosure () -> String, category: String) {
    AppFoundationLogger.debug(message(), category: category)
}

@inline(__always) func logInfo(_ message: @autoclosure () -> String, category: String) {
    AppFoundationLogger.info(message(), category: category)
}

@inline(__always) func logWarning(_ message: @autoclosure () -> String, category: String) {
    AppFoundationLogger.warning(message(), category: category)
}

@inline(__always) func logError(_ message: @autoclosure () -> String, category: String) {
    AppFoundationLogger.error(message(), category: category)
}
