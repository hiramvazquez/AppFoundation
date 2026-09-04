import AppFoundation
import CoreNetworking
import Foundation

// MARK: - The domain model

/// What a successful login produces. `Sendable`/`Equatable` for the same reason every
/// domain model in this example is: it crosses actor boundaries (`Logic` runs its network
/// call off whatever context called it) and tests compare it directly.
public nonisolated struct Session: Sendable, Equatable {
    public let token: String

    public init(token: String) {
        self.token = token
    }
}

// MARK: - Domain errors (ARQUITECTURA-KIT-2026-09-02.md §8, M1)

/// The error envelope this hypothetical backend returns for failures it doesn't already
/// classify through a well-known HTTP status — `{"error": {"code": "...", "detail": "..."}}`.
/// A real app decodes ITS OWN envelope this way; CoreNetworking never interprets the body
/// itself, only keeps it in `APIError.response`. Only `LoginLogic` (never `LoginViewModel`
/// or `AppErrorPresenter`) knows this type exists — the `Service`/`Logic` boundary is
/// exactly where a `Response` DTO is translated to domain (M2).
nonisolated struct ServerProblem: Decodable, Sendable, Equatable {
    nonisolated struct Body: Decodable, Sendable, Equatable {
        let code: String
        let detail: String
    }
    let error: Body
}

/// Every way logging in can fail, from this feature's point of view — never `APIError`,
/// which stops at the `Logic`/`Service` boundary (M1). Conforms `DomainError`
/// (AppFoundation): it presents its own copy (`AppErrorConvertible`) and says whether
/// retrying is worth offering (`isRetryable`).
public enum LoginError: DomainError, Equatable {
    case emptyEmail
    case emptyPassword
    case invalidCredentials
    case offline
    case server(message: String?)
    case unknown
    /// The login request was cancelled (e.g. the user left the screen mid-request) — not a
    /// failure. Kept as a `LoginError` case (instead of letting `mapError` fall through to
    /// `.unknown`) precisely so `AppCancellationRecognizer` can recognize it AFTER
    /// `LoginLogic` has already translated `APIError` away (`AppCancellationRecognizer.swift`
    /// explains why a recognizer that only understands `APIError.isCancellation` isn't
    /// enough here). `screenError`/`isRetryable` below are never actually used —
    /// `BaseViewModel` filters this case out before `AppErrorPresenter` ever sees it — they
    /// exist only because `DomainError` requires an exhaustive implementation.
    case cancelled

    public var isRetryable: Bool {
        switch self {
        case .offline, .server, .unknown: true
        case .emptyEmail, .emptyPassword, .invalidCredentials, .cancelled: false
        }
    }

    public var screenError: ScreenError {
        switch self {
        case .emptyEmail:
            return ScreenError(title: "Missing email", message: "Enter your email address.")
        case .emptyPassword:
            return ScreenError(title: "Missing password", message: "Enter your password.")
        case .invalidCredentials:
            return ScreenError(
                title: "Invalid credentials",
                message: "Check your email and password and try again."
            )
        case .offline:
            return ScreenError(title: "No connection", message: "Check your network and try again.")
        case .server(let message):
            return ScreenError(title: "Something went wrong", message: message ?? "Please try again later.")
        case .unknown:
            return ScreenError(title: "Something went wrong", message: "Please try again.")
        case .cancelled:
            // Unreachable in practice — see the case's doc comment.
            return ScreenError(title: "Cancelled", message: "The request was cancelled.")
        }
    }
}

// MARK: - Logic

/// Every operation `LoginViewModel` can ask its `Logic` for. `Logic`-conforming (the
/// AppFoundation marker, `ARQUITECTURA-KIT-2026-09-02.md` §1-2): a `ViewModel` depends on
/// this protocol through `init`, never on the concrete `LoginLogic` class.
public protocol LoginLogicProtocol: Logic {
    /// Validates `email`/`password` locally, delegates to `LoginServicing`, persists the
    /// resulting session, and maps any failure to `LoginError`.
    func login(email: String, password: String) async throws -> Session
}

/// The only implementation of `LoginLogicProtocol` this app ships: ALL of the feature's
/// business logic lives here, not in `LoginViewModel` (which only orchestrates) and not in
/// `LoginService` (which only knows how to make the one API call).
///
/// `nonisolated` (M5): a `Logic` is not tied to the main actor — with
/// `NonisolatedNonsendingByDefault` (enabled in `Package.swift`), its `async` methods run
/// on whichever actor calls them (here, `LoginViewModel`'s `@MainActor`) without forcing a
/// hop for work that doesn't need one.
public nonisolated final class LoginLogic: LoginLogicProtocol {
    private let loginService: any LoginServicing
    private let sessionStore: any SessionStoring

    /// - Parameters:
    ///   - loginService: The one API call this feature makes. Injected as a protocol —
    ///     `LoginLogic` never sees `APIServiceProtocol`/`BaseRequest` directly.
    ///   - sessionStore: Where a successful login's token is persisted, so subsequent
    ///     requests (via `BearerTokenInterceptor`, wired in `LoginService.swift`) can read
    ///     it. Injected as a protocol, same as `loginService`.
    public init(loginService: any LoginServicing, sessionStore: any SessionStoring) {
        self.loginService = loginService
        self.sessionStore = sessionStore
    }

    public func login(email: String, password: String) async throws -> Session {
        guard !email.isEmpty else { throw LoginError.emptyEmail }
        guard !password.isEmpty else { throw LoginError.emptyPassword }

        do {
            let session = try await loginService.login(email: email, password: password)
            await sessionStore.save(session.token)
            return session
        } catch {
            // `loginService.login` is `throws(APIError)` (typed throws): `error` here is
            // already `APIError`, not `any Error` — no cast needed.
            throw Self.mapError(error)
        }
    }

    /// The ONE place `APIError` gets translated to `LoginError` — everything past this
    /// method (`LoginViewModel`, `AppErrorPresenter`) only ever sees the result.
    private static func mapError(_ error: APIError) -> LoginError {
        switch error.category {
        case .cancelled:
            // NOT `.unknown`: a cancelled request is never a login failure, and falling
            // through here is exactly the bug this case exists to avoid — see
            // `LoginError.cancelled`'s doc comment and `AppCancellationRecognizer`.
            return .cancelled
        case .offline:
            return .offline
        case .unauthorized:
            return .invalidCredentials
        case .server:
            let detail = (try? error.decodeBody(ServerProblem.self))?.error.detail
            return .server(message: detail)
        default:
            return .unknown
        }
    }
}
