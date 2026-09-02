#if canImport(SwiftUI)
import SwiftUI

public extension View {
    /// Wraps `self` with `ScreenContainer`'s chrome/phase/activity/alert/banner rendering
    /// for a **read-only** `ScreenState` (AF-05) — no actions, no `ActionSender`. Idiomatic
    /// for a screen whose view model has nothing to `handle(_:)`: navigation, dependency
    /// injection, and read-only computed properties are enough.
    ///
    /// Reach for `ScreenContainer(_:chrome:content:)` instead when the screen's view model
    /// also conforms to `ActionHandling` and needs the single action entry point.
    ///
    /// ```swift
    /// struct DashboardView: View {
    ///     let viewModel: DashboardViewModel   // a BaseViewModel with no ActionHandling
    ///
    ///     var body: some View {
    ///         DashboardContent(viewModel: viewModel)
    ///             .screen(viewModel)
    ///     }
    /// }
    /// ```
    func screen<State: ScreenState>(_ state: State, chrome: ScreenChrome = .native) -> some View {
        ScreenContainer(observing: state, chrome: chrome) { self }
    }
}

#endif
