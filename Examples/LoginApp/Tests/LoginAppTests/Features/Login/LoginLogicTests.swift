import CoreNetworking
import Foundation
import Testing

@testable import LoginApp

/// `LoginLogic` tested purely against `LoginServiceMock`/`SessionStoreSpy` — no
/// `APIService`, no SwiftUI, no `ViewModel` involved: the local validation rule and the
/// `APIError` → `LoginError` mapping (M1) are exercised WITHOUT ever reaching the network.
@Suite("LoginLogic")
struct LoginLogicTests {
    @Test("An empty email throws LoginError.emptyEmail before calling the service")
    func emptyEmailNeverReachesTheService() async {
        let service = LoginServiceMock()
        let logic = LoginLogic(loginService: service, sessionStore: SessionStoreSpy())

        await #expect(throws: LoginError.emptyEmail) {
            _ = try await logic.login(email: "", password: "secret")
        }
        #expect(await service.logins.isEmpty)
    }

    @Test("An empty password throws LoginError.emptyPassword before calling the service")
    func emptyPasswordNeverReachesTheService() async {
        let service = LoginServiceMock()
        let logic = LoginLogic(loginService: service, sessionStore: SessionStoreSpy())

        await #expect(throws: LoginError.emptyPassword) {
            _ = try await logic.login(email: "hiram@example.com", password: "")
        }
        #expect(await service.logins.isEmpty)
    }

    @Test("Valid credentials delegate to LoginServicing, persist the session, and return it")
    func validCredentialsDelegateAndPersist() async throws {
        let service = LoginServiceMock(result: .success(Session(token: "delegated-token")))
        let sessionStore = SessionStoreSpy()
        let logic = LoginLogic(loginService: service, sessionStore: sessionStore)

        let session = try await logic.login(email: "hiram@example.com", password: "secret")

        #expect(session == Session(token: "delegated-token"))
        #expect(await service.logins.calls.map(\.email) == ["hiram@example.com"])
        #expect(await service.logins.calls.map(\.password) == ["secret"])
        #expect(await sessionStore.savedTokens.calls == ["delegated-token"])
    }

    @Test("An unauthorized service failure maps to LoginError.invalidCredentials — never APIError")
    func unauthorizedFailureMapsToDomainError() async {
        let service = LoginServiceMock(result: .failure(.stub(code: .httpStatus, statusCode: 401)))
        let sessionStore = SessionStoreSpy()
        let logic = LoginLogic(loginService: service, sessionStore: sessionStore)

        await #expect(throws: LoginError.invalidCredentials) {
            _ = try await logic.login(email: "hiram@example.com", password: "secret")
        }
        // A failed login never persists a session.
        #expect(await sessionStore.savedTokens.isEmpty)
    }

    @Test("An offline transport failure maps to LoginError.offline")
    func offlineFailureMapsToDomainError() async {
        let service = LoginServiceMock(
            result: .failure(.stub(code: .transport, underlying: URLError(.notConnectedToInternet)))
        )
        let logic = LoginLogic(loginService: service, sessionStore: SessionStoreSpy())

        await #expect(throws: LoginError.offline) {
            _ = try await logic.login(email: "hiram@example.com", password: "secret")
        }
    }

    @Test("A cancelled service failure maps to LoginError.cancelled — never .unknown")
    func cancelledFailureMapsToCancelledNotUnknown() async {
        let service = LoginServiceMock(result: .failure(.stub(code: .cancelled)))
        let logic = LoginLogic(loginService: service, sessionStore: SessionStoreSpy())

        await #expect(throws: LoginError.cancelled) {
            _ = try await logic.login(email: "hiram@example.com", password: "secret")
        }
    }
}
