import AppFoundation
import CoreNetworking
import Foundation

/// This app's `CancellationRecognizing` — the conceptual sibling of `AppErrorPresenter`
/// (`AppErrorPresenter.swift`): both extend a `BaseViewModel` default to understand what
/// THIS app's errors look like, because AppFoundation cannot import CoreNetworking (or any
/// app-specific error type) to teach the defaults on its own.
///
/// `DefaultCancellationRecognizer` only recognizes `CancellationError` and
/// `URLError(.cancelled)`. Two shapes of cancellation it can't see, both of which this app
/// needs recognized:
///
/// 1. A raw `CoreNetworking.APIError(code: .cancelled)` — reaches a view model whenever a
///    `Logic`/`Service` forwards a `CoreNetworking` failure without translating it first.
/// 2. `LoginError.cancelled` — `LoginLogic.mapError` (`LoginLogic.swift`) already translates
///    a cancelled `APIError` into `LoginError` before `login()` ever returns (M1: only
///    `LoginLogic` sees `APIError`), so by the time `BaseViewModel` sees the error it is
///    `LoginError`, not `APIError` anymore. A recognizer that only checked
///    `APIError.isCancellation` would never fire for THIS feature's own cancellations —
///    checking `LoginError` too is what actually closes the gap `LoginError.mapError`
///    documents.
///
/// Delegates to `DefaultCancellationRecognizer` for everything it already knows, instead of
/// duplicating that logic.
///
/// Register it once at app startup, alongside `AppErrorPresenter` (see `LoginModule`):
/// ```swift
/// BaseViewModel.cancellationRecognizer = AppCancellationRecognizer()
/// ```
public struct AppCancellationRecognizer: CancellationRecognizing {
    public init() {}

    public func isCancellation(_ error: any Error) -> Bool {
        if DefaultCancellationRecognizer().isCancellation(error) { return true }
        if let apiError = error as? APIError, apiError.isCancellation { return true }
        if let loginError = error as? LoginError, loginError == .cancelled { return true }
        return false
    }
}
