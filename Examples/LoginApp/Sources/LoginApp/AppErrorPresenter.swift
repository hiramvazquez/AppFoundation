import AppFoundation
import Foundation

/// The single place this app maps an error to `ScreenError` copy — and, since `LoginLogic`
/// already translated every `APIError` into `LoginError` (M1), the only error type it ever
/// has to reason about is `any DomainError`. `LoginViewModel` and this presenter never
/// import CoreNetworking or see `APIError`.
///
/// `DefaultErrorPresenter` already resolves `AppErrorConvertible` (which `DomainError`
/// composes) on its own — this presenter exists to add ONE thing on top: it only offers
/// `retry` when `isRetryable` says the operation is worth repeating, instead of attaching
/// it unconditionally the way `DefaultErrorPresenter` does for every `AppErrorConvertible`.
///
/// Register it once at app startup:
/// ```swift
/// BaseViewModel.errorPresenter = AppErrorPresenter()
/// ```
public struct AppErrorPresenter: ErrorPresenting {
    public init() {}

    public func screenError(for error: any Error, fallbackTitle: String, retry: Action?) -> ScreenError {
        guard let domainError = error as? any DomainError else {
            return DefaultErrorPresenter().screenError(for: error, fallbackTitle: fallbackTitle, retry: retry)
        }

        let base = domainError.screenError
        return ScreenError(
            title: base.title,
            message: base.message,
            retry: domainError.isRetryable ? (retry ?? base.retry) : nil
        )
    }
}
