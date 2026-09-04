import CoreNetworking
import CoreNetworkingTestSupport
import Foundation
import Testing

@testable import LoginApp

/// `LoginViewModel` tested purely against `LoginLogicMock` — no `LoginService`, no
/// `APIService`, no network involved, exactly the point of injecting `logic` as a
/// protocol.
@Suite("LoginViewModel")
@MainActor
struct LoginViewModelTests {
    @Test("handle(.updateEmail) / handle(.updatePassword) update local state")
    func updatesEditFields() {
        let viewModel = LoginViewModel(logic: LoginLogicMock())

        viewModel.handle(.updateEmail("hiram@example.com"))
        viewModel.handle(.updatePassword("secret"))

        #expect(viewModel.email == "hiram@example.com")
        #expect(viewModel.password == "secret")
    }

    @Test("handle(.login) calls logic.login with the current fields and reaches .content")
    func loginReachesContent() async {
        let mock = LoginLogicMock()
        mock.result = .success(Session(token: "abc123"))
        let viewModel = LoginViewModel(logic: mock)
        viewModel.handle(.updateEmail("hiram@example.com"))
        viewModel.handle(.updatePassword("secret"))

        viewModel.handle(.login)
        await viewModel.inFlightLoad?.value

        #expect(viewModel.phase == .content)
        #expect(viewModel.session == Session(token: "abc123"))
        #expect(await mock.logins.calls.map(\.email) == ["hiram@example.com"])
        #expect(await mock.logins.calls.map(\.password) == ["secret"])
    }

    @Test("A failing logic.login lands on .error, mapped through AppErrorPresenter")
    func loginFailureSurfacesError() async {
        let mock = LoginLogicMock()
        mock.result = .failure(LoginError.emptyPassword)
        let viewModel = LoginViewModel(logic: mock, errorPresenter: AppErrorPresenter())

        viewModel.handle(.login)
        await viewModel.inFlightLoad?.value

        #expect(viewModel.hasError)
        #expect(viewModel.currentError?.title == "Missing password")
    }

    @Test(
        "A cancelled APIError from LoginServiceMock, through the real LoginLogic, never reaches phase == .error"
    )
    func cancelledLoginNeverSurfacesAsError() async {
        // The full seam this test exists for: a REAL `LoginLogic` (not `LoginLogicMock`)
        // translating a REAL `CoreNetworking.APIError(code: .cancelled)` into
        // `LoginError.cancelled`, with `AppCancellationRecognizer` registered — exactly what
        // `LoginModule`'s doc comment tells a consumer to wire up.
        let service = LoginServiceMock(result: .failure(.stub(code: .cancelled)))
        let logic = LoginLogic(loginService: service, sessionStore: SessionStoreSpy())
        let viewModel = LoginViewModel(
            logic: logic,
            errorPresenter: AppErrorPresenter(),
            cancellationRecognizer: AppCancellationRecognizer()
        )
        viewModel.handle(.updateEmail("hiram@example.com"))
        viewModel.handle(.updatePassword("secret"))

        viewModel.handle(.login)
        await viewModel.inFlightLoad?.value

        #expect(!viewModel.hasError)
    }
}
