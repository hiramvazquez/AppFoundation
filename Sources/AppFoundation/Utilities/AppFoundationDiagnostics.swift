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

    // MARK: - Nonisolated entry point (AF-11: ResourceBundle's silent bundle-lookup fallback)

    /// `internal`, no `public` como su hermano `assertOnDroppedAction`: esto existe solo para
    /// que los tests del propio paquete observen el fallo (lo alcanzan con `@testable`), no
    /// para que una app lo configure. Hacerlo público el día que haga falta es aditivo.
    ///
    /// Like `assertOnDroppedAction`, but for diagnostics reported from `nonisolated` code
    /// that cannot touch a `@MainActor` static var synchronously.
    ///
    /// `nonisolated(unsafe)`: a `Bool` that test code sets once, before triggering the
    /// nonisolated failure it wants to observe, and that `reportNonisolatedFailure` only
    /// reads — the same "configure before exercising, don't race" contract
    /// `droppedActionHandler`'s callers already follow, just without an actor to enforce
    /// the serialization (see `ResourceBundleTests`, `.serialized`, for how tests honor it).
    /// Defaults to `false`. Only observed in `DEBUG` builds.
    nonisolated(unsafe) static var assertOnNonisolatedFailure = false

    /// Like `droppedActionHandler`, but `nonisolated` and `@Sendable` so `nonisolated` code
    /// can invoke it directly, from any thread, without an actor hop. Meant for tests that
    /// verify a `nonisolated` failure is reported; `nil` by default. Only invoked in `DEBUG`
    /// builds.
    nonisolated(unsafe) static var nonisolatedFailureHandler: (@Sendable (String) -> Void)?

    /// Reports one failure from a `nonisolated` context: logs it through `os.Logger`,
    /// forwards it to `nonisolatedFailureHandler`, and asserts if `assertOnNonisolatedFailure`
    /// is set. Compiles to nothing outside `DEBUG` — release builds must not crash over a
    /// diagnostic.
    ///
    /// `nonisolated` — unlike `reportDrop` — so a caller that is itself `nonisolated` (like
    /// `ResourceBundle`, whose whole reason to exist is staying `nonisolated` under
    /// `defaultIsolation(MainActor.self)`) can call this synchronously, from whatever thread
    /// first triggers its one-time lazy state, without hopping to the main actor.
    static nonisolated func reportNonisolatedFailure(_ message: @autoclosure () -> String) {
        #if DEBUG
        let message = message()
        AppFoundationLogger.resourceBundle.error("\(message, privacy: .public)")
        nonisolatedFailureHandler?(message)
        if assertOnNonisolatedFailure {
            assertionFailure(message)
        }
        #endif
    }
}
