import AppFoundationTestSupport
import CoreNetworking
import Foundation

@testable import LoginApp

/// Spy standing in for `LoginServicing` in `LoginLogicTests` — `LoginLogic` under test
/// never touches `APIServiceProtocol`/a real network pipeline.
///
/// `actor`, not a `Sendable`-conforming class with a `var` (M5: a `Servicing` conformance
/// is `Sendable`, and an actor is the straightforward way to hold mutable stubbed state
/// behind that requirement — the same shape `MockAPIService` uses in
/// `CoreNetworkingTestSupport`, there behind a lock instead since it predates this
/// package's actor-first test-double convention).
actor LoginServiceMock: LoginServicing {
    let logins = SpyRecorder<(email: String, password: String)>()
    private var result: Result<Session, APIError>

    init(result: Result<Session, APIError> = .success(Session(token: "stub-token"))) {
        self.result = result
    }

    func setResult(_ result: Result<Session, APIError>) {
        self.result = result
    }

    func login(email: String, password: String) async throws(APIError) -> Session {
        await logins.record((email, password))
        switch result {
        case .success(let session): return session
        case .failure(let error): throw error
        }
    }
}

/// Spy standing in for `SessionStoring` in `LoginLogicTests` — records what `LoginLogic`
/// persists on a successful login.
actor SessionStoreSpy: SessionStoring {
    let savedTokens = SpyRecorder<String>()
    let invalidateCalls = SpyRecorder<Void>()
    private var stubbedToken: String?

    init(stubbedToken: String? = nil) {
        self.stubbedToken = stubbedToken
    }

    func currentToken() async -> String? { stubbedToken }

    func save(_ token: String) async {
        stubbedToken = token
        await savedTokens.record(token)
    }

    func invalidate() async {
        stubbedToken = nil
        await invalidateCalls.record()
    }
}

/// Spy standing in for `SessionExpiring` in the Service-level "refresh fails → logout"
/// test (`LoginServiceTests`, ARQUITECTURA-KIT-2026-09-02.md §8, M6).
actor SessionExpiringSpy: SessionExpiring {
    let expiredCalls = SpyRecorder<Void>()

    func sessionDidExpire() async {
        await expiredCalls.record()
    }
}
