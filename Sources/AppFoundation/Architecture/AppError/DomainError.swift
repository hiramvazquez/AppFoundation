/// An error that crosses the `Logic` → `ViewModel` boundary in the View → ViewModel →
/// Logic → Services/Stores architecture (`ARQUITECTURA-KIT-2026-09-02.md` §8, M1).
///
/// A `Service` throws whatever error its transport produces (a network `Service` throws
/// `APIError`, say) — that error is specific to HOW the data was fetched, not to what the
/// feature means by "this failed". A `Logic` translates it into a `DomainError` of its
/// own feature (`LoginError.invalidCredentials`, `.offline`, `.unknown`) before it ever
/// reaches the `ViewModel`: the `ViewModel` and the app's `ErrorPresenting` never see
/// `APIError`, SwiftData's error type, or any other transport-specific error — only
/// `DomainError`. That is what keeps `ErrorPresenting` working identically across all
/// four variants (solo API, solo local, API + local, sin datos): the presenter maps
/// domain errors, never transport ones.
///
/// `DomainError` composes `AppErrorConvertible` (so it presents its own copy with no
/// `ErrorPresenting` needing to know the feature's error type — see the README,
/// "AppErrorConvertible: the easiest way to plug in a domain error") and adds exactly one
/// thing: `isRetryable`, so a presenter can decide whether to offer a retry action without
/// re-deriving that from the underlying transport error a `ViewModel` never sees.
///
/// ```swift
/// enum LoginError: DomainError, Equatable {
///     case invalidCredentials
///     case offline
///     case unknown
///
///     var isRetryable: Bool {
///         switch self {
///         case .offline: true
///         case .invalidCredentials, .unknown: false
///         }
///     }
///
///     var screenError: ScreenError {
///         switch self {
///         case .invalidCredentials:
///             ScreenError(title: "Invalid credentials", message: "Check your email and password.")
///         case .offline:
///             ScreenError(title: "No connection", message: "Check your network and try again.")
///         case .unknown:
///             ScreenError(title: "Something went wrong", message: "Please try again.")
///         }
///     }
/// }
///
/// // In LoginLogic:
/// func login(email: String, password: String) async throws -> Session {
///     do {
///         return try await loginService.login(email: email, password: password)
///     } catch let error as APIError {
///         throw Self.mapError(error)   // -> LoginError
///     }
/// }
/// ```
///
/// `Sendable`, like `AppErrorConvertible`'s own `Error` requirement expects in this
/// package's `@MainActor`-heavy call sites: a `DomainError` crosses from a `nonisolated`
/// `Logic` method back to a `@MainActor` `ViewModel`.
public protocol DomainError: Error, AppErrorConvertible, Sendable {
    /// Whether retrying the operation that threw this error may succeed. Doesn't attach a
    /// retry action by itself — a presenter reads it to decide whether to offer one, since
    /// `AppErrorConvertible.screenError` alone has no closure to attach.
    var isRetryable: Bool { get }
}

extension DomainError {
    /// Conservative default: an error a feature doesn't override this for is treated as
    /// not worth retrying blindly.
    public var isRetryable: Bool { false }
}
