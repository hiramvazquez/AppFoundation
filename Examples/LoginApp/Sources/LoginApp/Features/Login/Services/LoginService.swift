import CoreNetworking
import Foundation

// MARK: - The request / response DTOs (M2: only this file ever sees them)

/// A typed endpoint the way CoreNetworking wants it: the type IS the request, and
/// `Response` says what `execute` gives back. `Response` is a DTO — `LoginService` maps it
/// to `Session` (the domain model) before returning; `LoginLogic`/`LoginViewModel` never
/// see `LoginRequest.Response`.
struct LoginRequest: BaseRequest {
    struct Body: Encodable, Sendable {
        let email: String
        let password: String
    }

    struct Response: Decodable, Sendable {
        let token: String
    }

    let path = "/login"
    let method = HTTPMethod.post
    let body: Body?

    init(email: String, password: String) {
        self.body = Body(email: email, password: password)
    }
}

// MARK: - The service

/// One API call: `POST /login` → a `Session`. `LoginServicing` is what `LoginLogic`
/// depends on through `init` — never this concrete type
/// (`ARQUITECTURA-KIT-2026-09-02.md` §1, rule 3). `struct Sendable` (M5): a `Service`
/// carries no mutable state of its own, only `api`.
public protocol LoginServicing: Sendable {
    func login(email: String, password: String) async throws(APIError) -> Session
}

/// The ONLY type in this app that references `APIServiceProtocol`/`BaseRequest` for the
/// login endpoint. Conforms to `EndpointService` for `call(_:)`, but nothing outside this
/// file ever sees that conformance.
public struct LoginService: LoginServicing, EndpointService {
    public let api: any APIServiceProtocol

    public init(api: any APIServiceProtocol) {
        self.api = api
    }

    public func login(email: String, password: String) async throws(APIError) -> Session {
        let response = try await call(LoginRequest(email: email, password: password))
        return Session(token: response.token)
    }
}

// MARK: - Wiring: a production APIService with bearer auth + refresh-on-401 + logout

/// Builds an `APIService` the way a production app would: a bearer token read fresh on
/// every request from `sessionStore`, and a retrier that refreshes it and replays the
/// request exactly once on a 401. When the refresh itself fails — not just the original
/// request — the session cannot recover: `sessionStore` is invalidated and
/// `sessionExpiring` is notified, so the app's root can route back to `LoginView`
/// (`ARQUITECTURA-KIT-2026-09-02.md` §8, M6).
///
/// This wiring lives here, not in `LoginModule`, because it is genuinely about HOW the
/// network layer authenticates requests — the same reasoning that keeps `APIServiceProtocol`
/// out of `LoginLogic` in the first place. `LoginModule` only calls this function; it never
/// constructs `BearerTokenInterceptor`/`TokenRefreshRetrier` itself.
public func makeAPIService(
    configuration: NetworkingConfiguration,
    transport: any HTTPTransport,
    sessionStore: any SessionStoring,
    sessionExpiring: any SessionExpiring,
    refreshToken: @escaping @Sendable () async throws -> String,
    clock: any Clock<Duration> = ContinuousClock()
) -> APIService {
    let refresher = TokenRefresher {
        do {
            let newToken = try await refreshToken()
            await sessionStore.save(newToken)
        } catch {
            await sessionStore.invalidate()
            await sessionExpiring.sessionDidExpire()
            throw error
        }
    }
    return APIService(
        configuration: configuration,
        transport: transport,
        interceptors: [BearerTokenInterceptor { await sessionStore.currentToken() }],
        retriers: [TokenRefreshRetrier(refresher: refresher)],
        clock: clock
    )
}
