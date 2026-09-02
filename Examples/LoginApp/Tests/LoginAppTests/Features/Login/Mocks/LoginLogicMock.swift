import AppFoundationTestSupport
import Foundation

@testable import LoginApp

/// Spy standing in for `LoginLogicProtocol` in `LoginViewModelTests` — the view model
/// under test never touches a real `LoginService`/`APIService`.
final class LoginLogicMock: LoginLogicProtocol {
    let logins = SpyRecorder<(email: String, password: String)>()
    var result: Result<Session, any Error> = .success(Session(token: "stub-token"))

    func login(email: String, password: String) async throws -> Session {
        await logins.record((email, password))
        return try result.get()
    }
}
