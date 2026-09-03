import Foundation

/// Development-time diagnostics for work that AppFoundation would otherwise drop
/// silently (PRD-X-05, A7).
///
/// Two places in the package hold their view model **weakly** by design — `ActionSender`
/// (built by `ActionHandling.sender`) and the `Task` bodies behind `performLoad`/
/// `performActivity`. When the view model is gone by the time they run, they do nothing:
/// no crash, no error, no state change. That is the right memory contract, but it turns
/// one specific mistake into a screen that stays empty ~50% of the time with nothing in
/// the console: a View that holds its view model with `let` instead of `@State`, so SwiftUI
/// re-running the View's initializer (a navigation destination builder during a push, for
/// example) replaces the instance that received `.load` with one that never does.
///
/// In `DEBUG` builds, every one of those drops is logged at `.error` level through
/// `os.Logger` (subsystem `AppFoundation`, category `ActionSender`), forwarded to
/// `droppedActionHandler` if set, and — when `assertOnDroppedAction` is `true` — turned
/// into an `assertionFailure`. In release builds nothing here runs: the properties exist
/// so app code that configures them compiles in every configuration, but no diagnostic is
/// ever emitted.
///
/// ```swift
/// // AppDelegate / App.init, only in DEBUG if you prefer:
/// AppFoundationDiagnostics.assertOnDroppedAction = true
/// ```
@MainActor
public enum AppFoundationDiagnostics {
    /// When `true`, a dropped action or skipped `performLoad`/`performActivity` work also
    /// triggers `assertionFailure` with the same message that was logged. Defaults to
    /// `false`. Only observed in `DEBUG` builds.
    public static var assertOnDroppedAction = false

    /// Receives the message of every dropped action / skipped work, after it was logged.
    /// Meant for tests that verify a drop is reported; `nil` by default. Only invoked in
    /// `DEBUG` builds.
    public static var droppedActionHandler: (@MainActor (String) -> Void)?

    /// Reports one drop: logs it, forwards it to `droppedActionHandler`, and asserts if
    /// `assertOnDroppedAction` is set. Compiles to nothing outside `DEBUG`.
    static func reportDrop(_ message: @autoclosure () -> String) {
        #if DEBUG
        let message = message()
        AppFoundationLogger.actionSender.error("\(message, privacy: .public)")
        droppedActionHandler?(message)
        if assertOnDroppedAction {
            assertionFailure(message)
        }
        #endif
    }
}
