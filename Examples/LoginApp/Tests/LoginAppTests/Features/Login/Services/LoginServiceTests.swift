import CoreNetworking
import CoreNetworkingTestSupport
import Foundation
import Testing

@testable import LoginApp

/// `LoginService` — the only type in this app that touches `APIServiceProtocol` — tested
/// two ways: stubbed (`MockAPIService`, the fast path for the happy/error case) and
/// against the real pipeline (`InMemoryTransport`, exercising retries/interceptors/token
/// refresh exactly like production).
@Suite("LoginService")
struct LoginServiceTests {
    // MARK: - MockAPIService

    @Test("A stubbed 200 decodes into a Session")
    func stubbedSuccessDecodesSession() async throws {
        let mock = MockAPIService()
        mock.stub(LoginRequest.self, returning: LoginRequest.Response(token: "abc123"))
        let service = LoginService(api: mock)

        let session = try await service.login(email: "hiram@example.com", password: "secret")

        #expect(session == Session(token: "abc123"))
    }

    @Test("A stubbed failure propagates as APIError")
    func stubbedFailurePropagates() async {
        let mock = MockAPIService()
        mock.stub(LoginRequest.self, throwing: .stub(code: .httpStatus, statusCode: 500))
        let service = LoginService(api: mock)

        do {
            _ = try await service.login(email: "hiram@example.com", password: "secret")
            Issue.record("Expected login(email:password:) to throw")
        } catch {
            #expect(error.statusCode == 500)
        }
    }

    // MARK: - InMemoryTransport: 401 → refresh → 200

    @Test("A 401 refreshes the token and the retried request lands on a Session")
    func unauthorizedRefreshesTokenAndRetrySucceeds() async throws {
        let transport = InMemoryTransport()
        let loginURL = URL(string: "https://unit.test/login")!
        await transport.register(
            InMemoryTransport.Exchange(
                method: .post,
                url: loginURL,
                responses: [
                    .response(status: 401),
                    .response(status: 200, body: #"{"token":"refreshed-session"}"#.data(using: .utf8)!)
                ]
            )
        )

        let clock = ManualClock()
        let sessionStore = SessionStoreSpy(stubbedToken: "expired-token")
        let api = makeAPIService(
            configuration: NetworkingConfiguration(baseURL: URL(string: "https://unit.test")!),
            transport: transport,
            sessionStore: sessionStore,
            sessionExpiring: SessionExpiringSpy(),
            refreshToken: { "refreshed-token" },
            clock: clock
        )
        let service = LoginService(api: api)

        async let sessionResult = service.login(email: "hiram@example.com", password: "secret")

        // The retrier's `.retry` decision still sleeps through the injected clock (jittered
        // backoff, same as a plain retry) — drive it by hand, no real wait.
        await clock.waitUntilSleeping()
        clock.advance(by: .seconds(1))

        let session = try await sessionResult

        #expect(session == Session(token: "refreshed-session"))
        let recorded = await transport.recorded
        #expect(recorded.count == 2)
        // The retried request carries the refreshed token, not the expired one.
        #expect(recorded.last?.value(forHTTPHeaderField: "Authorization") == "Bearer refreshed-token")
        #expect(await sessionStore.savedTokens.calls == ["refreshed-token"])
    }

    // MARK: - InMemoryTransport: refresh itself fails → logout (M6)

    @Test("When the refresh call itself fails, the session is invalidated and sessionExpiring is notified")
    func refreshFailureInvalidatesSessionAndNotifiesExpiry() async throws {
        let transport = InMemoryTransport()
        let loginURL = URL(string: "https://unit.test/login")!
        await transport.register(
            InMemoryTransport.Exchange(
                method: .post,
                url: loginURL,
                response: .response(status: 401)
            )
        )

        let clock = ManualClock()
        let sessionStore = SessionStoreSpy(stubbedToken: "expired-token")
        let sessionExpiring = SessionExpiringSpy()
        struct RefreshTokenExpired: Error {}
        let api = makeAPIService(
            configuration: NetworkingConfiguration(baseURL: URL(string: "https://unit.test")!),
            transport: transport,
            sessionStore: sessionStore,
            sessionExpiring: sessionExpiring,
            refreshToken: { throw RefreshTokenExpired() },
            clock: clock
        )
        let service = LoginService(api: api)

        do {
            _ = try await service.login(email: "hiram@example.com", password: "secret")
            Issue.record("Expected login(email:password:) to throw")
        } catch {
            // The ORIGINAL 401 reaches the caller unchanged — `TokenRefreshRetrier`
            // answers `.doNotRetry` when the refresh itself fails.
            #expect(error.statusCode == 401)
        }

        let recorded = await transport.recorded
        #expect(recorded.count == 1)
        #expect(await sessionStore.invalidateCalls.count == 1)
        #expect(await sessionExpiring.expiredCalls.count == 1)
    }
}
