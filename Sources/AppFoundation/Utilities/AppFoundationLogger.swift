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
    /// Errors that reach `DefaultErrorPresenter`'s generic fallback — i.e. errors that
    /// are neither `AppErrorConvertible` nor `LocalizedError`. The technical detail goes
    /// here (`.private`), never to the screen.
    static let errors = Logger(subsystem: subsystem, category: "Errors")

    /// Actions dropped by `ActionSender` and `performLoad`/`performActivity` work skipped
    /// because the view model was already deallocated (`AppFoundationDiagnostics`, A7).
    /// DEBUG only.
    static let actionSender = Logger(subsystem: subsystem, category: "ActionSender")
}
