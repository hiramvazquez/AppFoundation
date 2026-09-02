/// AppFoundation — a single-package foundation for SwiftUI apps.
///
/// AppFoundation bundles the pieces most greenfield apps need from day one:
///
/// - `BaseViewModel` for primary screen state and secondary activity handling
/// - `ScreenState` and `ActionHandling` for the screen ↔ shell contract: `ScreenContainer`
///   depends on these protocols, never on the concrete `BaseViewModel` class, and a view's
///   only way to act on a screen is `ActionSender<Action>` — never the view model itself
/// - `Coordinator`, `Router`, and `CoordinatorView` for navigation
/// - `Container` and `@Inject` for lightweight DI
/// - `ScreenContainer` for shell UI and screen-state rendering
/// - small utilities such as `Debouncer`, `Throttler`, `WrappedError`, and `AppEnvironment`
///
/// The package is intentionally opinionated: it is meant to be adopted as a cohesive baseline,
/// not as a bag of unrelated helpers.
public enum AppFoundation {}
