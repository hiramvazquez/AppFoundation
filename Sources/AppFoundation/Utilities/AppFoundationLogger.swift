import os

/// Internal logging used by AppFoundation, backed by `os.Logger`.
///
/// `print()` is not logging: `os.Logger` provides categories, levels, and — critically —
/// privacy redaction. Callers interpolate any value that could identify a user (route
/// payloads, dynamic content) with `privacy: .private`; static operation names may be
/// interpolated with `privacy: .public`.
nonisolated enum AppFoundationLogger {
    private static let subsystem = "AppFoundation"

    /// Navigation events (push/pop/present) from `Coordinator`.
    static let navigation = Logger(subsystem: subsystem, category: "Navigation")

    /// Dependency-injection registration/resolution diagnostics from `Container`.
    static let di = Logger(subsystem: subsystem, category: "DI")

    /// Runtime environment diagnostics from `AppEnvironment`.
    static let environment = Logger(subsystem: subsystem, category: "Environment")
}
