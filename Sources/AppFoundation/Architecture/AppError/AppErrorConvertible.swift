import Foundation

/// Protocol for errors that can be converted to user-facing screen errors.
///
/// Conform to this protocol to allow your domain errors to be displayed
/// in the UI through the `ScreenError` type. This enables clean separation
/// between your backend/domain errors and user-facing error messaging.
///
/// ## Example
/// ```swift
/// enum APIError: Error, Equatable, Sendable {
///     case networkFailure
///     case invalidResponse
///     case serverError(Int)
/// }
///
/// extension APIError: AppErrorConvertible {
///     var screenError: ScreenError {
///         switch self {
///         case .networkFailure:
///             return ScreenError(
///                 title: "Network Error",
///                 message: "Unable to connect. Please check your connection."
///             )
///         case .invalidResponse:
///             return ScreenError(
///                 title: "Invalid Response",
///                 message: "The server returned unexpected data."
///             )
///         case .serverError(let code):
///             return ScreenError(
///                 title: "Server Error",
///                 message: "Server returned error code \(code). Please try again."
///             )
///         }
///     }
/// }
///
/// // In your view model:
/// func loadData() {
///     load {
///         try await fetchData()
///     }
/// }
///
/// func loadData() throws {
///     do {
///         try await service.fetchData()
///     } catch let error as APIError {
///         setError(error.screenError)
///     }
/// }
/// ```
public nonisolated protocol AppErrorConvertible: Error {
    /// Converts this error to a user-facing `ScreenError`.
    ///
    /// Implement this to provide user-friendly error messaging for your domain errors.
    /// You can customize the title, message, and optionally provide a retry action.
    var screenError: ScreenError { get }
}
