import Foundation
import Observation

/// Notified when a session can no longer be recovered — a refresh attempt itself failed,
/// not merely a single request's 401 (`ARQUITECTURA-KIT-2026-09-02.md` §8, M6: "logout
/// global"). Implemented by whatever the app's root observes; wired into
/// `makeAPIService(sessionExpiring:)` (`LoginService.swift`), never called directly by
/// `LoginLogic`.
public protocol SessionExpiring: Sendable {
    func sessionDidExpire() async
}

/// What a real app's root view (its own `CoordinatorView`, in a full app — this example
/// package has no navigation shell of its own) observes to route back to `LoginView`:
///
/// ```swift
/// struct RootView: View {
///     @State private var session = Container.shared.resolve(AppSessionState.self)
///
///     var body: some View {
///         if session.isLoggedOut {
///             LoginView(viewModel: Container.shared.resolve())
///         } else {
///             HomeView(...)
///         }
///     }
/// }
/// ```
///
/// `@MainActor`/`@Observable`, like every other piece of visible app state in this
/// architecture — `sessionDidExpire()` is called from `TokenRefreshRetrier`'s (nonisolated,
/// off-main-actor) failure path, so it hops back to the main actor to flip
/// `isLoggedOut`, the same way `BaseViewModel`'s phase transitions always run on the
/// main actor.
@MainActor
@Observable
public final class AppSessionState: SessionExpiring {
    // Explicit, nonisolated deinit (linter rule R16): avoids the synthesized isolated deinit
    // and its back-deploy shim on older OS versions. Nothing to clean up.
    deinit {}

    public private(set) var isLoggedOut = false

    public init() {}

    public func sessionDidExpire() async {
        isLoggedOut = true
    }
}
