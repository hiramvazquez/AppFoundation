import AppFoundation
import CoreNetworking
import Foundation

/// Registers every layer of the Login feature into a `Container`: the composition root is
/// the only place that knows the concrete types (`SessionStore`, `LoginService`,
/// `LoginLogic`) behind their protocols — everything downstream (`LoginLogic`,
/// `LoginViewModel`) only ever sees `any SessionStoring`/`any LoginServicing`/
/// `any LoginLogicProtocol` (M4: no layer below this file calls `Container.shared` or
/// `@Inject` on its own).
///
/// A real app's `@main` would call this once at startup:
/// ```swift
/// Container.shared.register(modules: [LoginModule(baseURL: URL(string: "https://api.myapp.com")!)])
/// BaseViewModel.errorPresenter = AppErrorPresenter()
/// BaseViewModel.cancellationRecognizer = AppCancellationRecognizer()
/// ```
/// and its root view would resolve `LoginViewModel`/`AppSessionState` from
/// `Container.shared` — never construct them by hand.
///
/// The `cancellationRecognizer` line above is the seam a consumer of BOTH AppFoundation and
/// CoreNetworking must not skip — see `AppCancellationRecognizer`'s doc comment for why
/// `DefaultCancellationRecognizer` alone lets a cancelled login surface as "Something went
/// wrong".
public struct LoginModule: DependencyModule {
    private let baseURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    public func register(in container: Container) {
        // MARK: Store
        container.register(SessionStore.self) { _ in SessionStore() }
        container.register(SessionStoring.self) { c in c.resolve(SessionStore.self) }

        // MARK: App-wide session observation (M6)
        container.register(AppSessionState.self) { _ in AppSessionState() }
        container.register(SessionExpiring.self) { c in c.resolve(AppSessionState.self) }

        // MARK: Networking wiring
        container.register(APIServiceProtocol.self) { c in
            makeAPIService(
                configuration: NetworkingConfiguration(baseURL: baseURL),
                transport: URLSessionTransport(),
                sessionStore: c.resolve(SessionStoring.self),
                sessionExpiring: c.resolve(SessionExpiring.self),
                refreshToken: {
                    // A real app would call its auth backend here.
                    "refreshed-token"
                }
            )
        }

        // MARK: Service
        container.register(LoginServicing.self) { c in
            LoginService(api: c.resolve())
        }

        // MARK: Logic
        container.register(LoginLogicProtocol.self) { c in
            LoginLogic(loginService: c.resolve(), sessionStore: c.resolve(SessionStoring.self))
        }

        // MARK: ViewModel — resolved by the root view, never constructed by Logic/Service/Store.
        container.register(LoginViewModel.self, lifecycle: .transient) { c in
            LoginViewModel(logic: c.resolve())
        }
    }
}
