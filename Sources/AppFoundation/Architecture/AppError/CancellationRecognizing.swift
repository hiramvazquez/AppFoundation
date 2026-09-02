import Foundation

/// Recognizes when a thrown error represents cancellation rather than failure.
///
/// `performLoad`/`performActivity` already treat a typed `CancellationError` as
/// cancellation (never surfaced as a screen error). Network layers, however, routinely
/// cancel through their own vocabulary — `URLError(.cancelled)` is the most common one —
/// and a `catch` that only recognizes `CancellationError` lets those slip through as
/// user-visible failures. Conform to this protocol to extend recognition to your app's
/// error types (e.g. an `APIError.cancelled` case) and assign the result to
/// `BaseViewModel.cancellationRecognizer`.
public protocol CancellationRecognizing: Sendable {
    /// Returns `true` when `error` represents cancellation and should never reach the
    /// user as a screen error, alert, or banner.
    func isCancellation(_ error: any Error) -> Bool
}

/// Default cancellation recognizer: typed `CancellationError` and `URLError(.cancelled)`.
///
/// Apps that layer their own error type over `URLError` (wrapping it, or mapping it to a
/// domain enum) should provide their own `CancellationRecognizing` that also understands
/// that type — see `BaseViewModel.cancellationRecognizer`.
public struct DefaultCancellationRecognizer: CancellationRecognizing {
    public init() {}

    public func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}
