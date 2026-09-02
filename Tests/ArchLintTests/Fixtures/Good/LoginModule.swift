import AppFoundation
import CoreNetworking
import Foundation

public struct LoginModule: DependencyModule {
    public init() {}

    public func register(in container: Container) {
        container.register(LoginServicing.self) { c in LoginService(api: c.resolve()) }
        container.register(LoginStoring.self) { _ in LoginStore() }
        container.register(LoginLogicProtocol.self) { c in
            LoginLogic(loginService: c.resolve(), loginStore: c.resolve())
        }
        container.register(LoginViewModel.self, lifecycle: .transient) { c in
            LoginViewModel(logic: c.resolve())
        }
    }
}
