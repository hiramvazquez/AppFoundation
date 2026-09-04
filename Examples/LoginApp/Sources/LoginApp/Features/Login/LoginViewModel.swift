import AppFoundation
import Foundation
import Observation

/// Orchestrates between `LoginView` and `LoginLogic`: receives an `Action`, calls
/// `logic`, updates screen state. Never imports CoreNetworking, never references the
/// networking layer or the concrete Login service type directly — only `logic`
/// (`ARQUITECTURA-KIT-2026-09-02.md` §1, rule 1).
@MainActor
@Observable
public final class LoginViewModel: LogicViewModel<any LoginLogicProtocol>, ActionHandling {
    public private(set) var email = ""
    public private(set) var password = ""
    public private(set) var session: Session?

    /// Every action `LoginView` recognizes.
    public enum Action: Sendable {
        case updateEmail(String)
        case updatePassword(String)
        case login
    }

    public init(logic: any LoginLogicProtocol, errorPresenter: (any ErrorPresenting)? = nil) {
        super.init(logic: logic, errorPresenter: errorPresenter)
    }

    public func handle(_ action: Action) {
        switch action {
        case .updateEmail(let email): self.email = email
        case .updatePassword(let password): self.password = password
        case .login: login()
        }
    }

    private func login() {
        performLoad { vm in
            let session = try await vm.logic.login(email: vm.email, password: vm.password)
            vm.session = session
        }
    }
}
