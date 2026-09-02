import Foundation

/// Maps any thrown error to the `ScreenError` shown to the user.
///
/// `BaseViewModel` never shows `error.localizedDescription` for a foreign `Error` — for
/// any Swift type that isn't `LocalizedError`, that string reads like
/// *"The operation couldn't be completed. (Module.Type error 9.)"*. An `ErrorPresenting`
/// is the single place an app maps errors to user-facing copy. Register one:
///
/// ```swift
/// struct AppErrorPresenter: ErrorPresenting {
///     func screenError(for error: any Error, fallbackTitle: String, retry: Action?) -> ScreenError {
///         if let network = error as? NetworkError {
///             switch network.category {
///             case .offline:
///                 return ScreenError(title: "No connection", message: "Check your network and try again.", retry: retry)
///             case .unauthorized:
///                 return ScreenError(title: "Session expired", message: "Please sign in again.")
///             default:
///                 break
///             }
///         }
///         return DefaultErrorPresenter().screenError(for: error, fallbackTitle: fallbackTitle, retry: retry)
///     }
/// }
///
/// // At app startup:
/// BaseViewModel.errorPresenter = AppErrorPresenter()
/// ```
public protocol ErrorPresenting: Sendable {
    /// Maps `error` to a `ScreenError`.
    ///
    /// - Parameters:
    ///   - error: The thrown error. Never a cancellation — `BaseViewModel` filters those
    ///     out through `CancellationRecognizing` before calling the presenter.
    ///   - fallbackTitle: The title to use when the error doesn't carry its own (the
    ///     `errorTitle` passed to `performLoad`, or `L10n.error`).
    ///   - retry: The action to retry the operation that threw, if any. Presenters that
    ///     want a domain-specific title/message but still offer retry should thread this
    ///     through to their `ScreenError`.
    func screenError(for error: any Error, fallbackTitle: String, retry: Action?) -> ScreenError
}

/// The default error presenter, used when no app-specific one is registered.
///
/// Resolution order:
/// 1. `AppErrorConvertible` — the error already knows how to present itself.
/// 2. `LocalizedError` with a non-`nil` `errorDescription` — `fallbackTitle` plus that
///    description.
/// 3. Anything else — `fallbackTitle` plus a generic, localized message
///    (`L10n.genericErrorMessage`). The technical detail is logged, never shown.
public struct DefaultErrorPresenter: ErrorPresenting {
    public init() {}

    public func screenError(for error: any Error, fallbackTitle: String, retry: Action?) -> ScreenError {
        if let convertible = error as? AppErrorConvertible {
            let base = convertible.screenError
            return ScreenError(title: base.title, message: base.message, retry: retry ?? base.retry)
        }

        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return ScreenError(title: fallbackTitle, message: description, retry: retry)
        }

        AppFoundationLogger.errors.error("unpresentable error: \(String(describing: error), privacy: .private)")
        return ScreenError(title: fallbackTitle, message: L10n.genericErrorMessage, retry: retry)
    }
}
