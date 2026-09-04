import Foundation

/// Optional base class for a `ViewModel` whose whole job is orchestration: receive an
/// `Action`, call its `Logic`, update screen state (`ARQUITECTURA-KIT-2026-09-02.md`
/// §1-2). `logic` is a `let` — it is provided once at construction and never swapped, the
/// same way `BaseViewModel`'s `errorPresenter`/`cancellationRecognizer`/`clock`
/// per-instance overrides work.
///
/// `LogicViewModel<L>` inherits every `BaseViewModel`/`LoadableViewModel` capability
/// (`phase`, `activity`, `alert`, `banner`, `performLoad`, `performActivity`, `handle`
/// helpers, memory/cancellation semantics) unchanged — it adds exactly one property. It
/// does **not** conform to `ActionHandling` itself: `Action` is screen-specific, so each
/// subclass declares its own `enum Action` and implements `handle(_:)`, exactly like a
/// plain `BaseViewModel` subclass would.
///
/// `L` is typically `any XxxLogicProtocol` — a protocol, never the concrete `XxxLogic`
/// class — so a test substitutes a spy without touching the view model's declaration:
///
/// ```swift
/// final class LoginViewModel: LogicViewModel<any LoginLogicProtocol>, ActionHandling {
///     enum Action: Sendable {
///         case login(email: String, password: String)
///     }
///
///     func handle(_ action: Action) {
///         switch action {
///         case .login(let email, let password):
///             performLoad { vm in
///                 _ = try await vm.logic.login(email: email, password: password)
///                 vm.setContent()
///             }
///         }
///     }
/// }
///
/// // Production:
/// LoginViewModel(logic: LoginLogic(loginService: LoginService(api: apiService)))
/// // Test:
/// LoginViewModel(logic: LoginLogicMock())
/// ```
///
/// A `ViewModel` built this way never imports CoreNetworking, never references
/// `APIService`/`URLSession`/a concrete `*Service`/`*Store` type, and never constructs its
/// `Logic` itself — only `LogicViewModel<L>.init(logic:)` receives it, always as a
/// protocol.
@MainActor
open class LogicViewModel<L>: BaseViewModel {
    // Explicit, nonisolated `deinit` on purpose. Under `defaultIsolation(MainActor)` a class
    // WITHOUT one gets a synthesized *isolated* deinit, which on OS versions older than the
    // toolchain's runtime goes through `swift_task_deinitOnExecutorMainActorBackDeploy`; two
    // of those nested (a ViewModel releasing its Coordinator) aborted with a libmalloc
    // double free on iOS 26.2 (AppStarter CI, Xcode 26.3). Nothing here needs the actor.
    deinit {}

    /// This view model's `Logic` — the only place its business logic lives. Injected once
    /// through `init`, never mutated afterwards.
    public let logic: L

    /// - Parameters:
    ///   - logic: The `Logic` this view model orchestrates against. Typically `any
    ///     XxxLogicProtocol`, so production code and tests can pass different
    ///     conformances without changing this view model's declaration.
    ///   - errorPresenter: Forwarded to `BaseViewModel.init(errorPresenter:)` — overrides
    ///     `BaseViewModel.errorPresenter` for this instance only.
    ///   - cancellationRecognizer: Forwarded to
    ///     `BaseViewModel.init(cancellationRecognizer:)`.
    ///   - clock: Forwarded to `BaseViewModel.init(clock:)`.
    public init(
        logic: L,
        errorPresenter: (any ErrorPresenting)? = nil,
        cancellationRecognizer: (any CancellationRecognizing)? = nil,
        clock: (any Clock<Duration>)? = nil
    ) {
        self.logic = logic
        super
            .init(
                errorPresenter: errorPresenter,
                cancellationRecognizer: cancellationRecognizer,
                clock: clock
            )
    }
}
