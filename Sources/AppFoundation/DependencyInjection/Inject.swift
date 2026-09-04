import Foundation

/// Property wrapper that lazily resolves a dependency from a container. **Last resort.**
///
/// `@Inject` is a service locator: it hides the dependency from the initializer, and it
/// traps at runtime — not at compile time — when the type is not registered. Keep it for
/// **leaf classes** (an analytics adapter, a logger wrapper) where threading the
/// dependency through every initializer costs more than it clarifies. Everything else
/// takes its dependencies through `init`.
///
/// ## Why not in Views
///
/// `Inject` is a class. Inside a `struct View` it is copied by reference and keeps its
/// cached value across view copies without being a `DynamicProperty` — SwiftUI cannot
/// see it and will not update the view when it changes. Views get their dependencies from
/// the native mechanism, `Environment` (`@Entry` on `EnvironmentValues`), which is
/// scoped to the view tree, overridable per subtree and understood by previews. See the
/// README's "Dependency injection" section for the side-by-side table.
///
/// ## Isolation
///
/// `Inject` is `@MainActor`, like `Container`: resolution is synchronous and happens
/// where the wrapped object lives. A `nonisolated` type does not use `@Inject`; it
/// receives its dependency already resolved through its initializer.
///
/// ## Contract
///
/// The wrapped type **must be registered** before first access; resolution of an
/// unregistered type traps (same contract as `Container.resolve`). `@Inject` does not
/// support optional dependencies — if absence is a valid state, resolve explicitly with
/// `Container.tryResolve` and model the optional yourself.
///
/// ## Example
/// ```swift
/// final class AnalyticsAdapter {
///     @Inject private var analytics: AnalyticsService
///
///     func track(_ event: String) {
///         analytics.log(event)
///     }
/// }
/// ```
///
/// ## Example - Overriding in Tests
/// ```swift
/// let container = Container(parent: .shared)
/// container.register(instance: MockAnalytics(), as: AnalyticsService.self)
/// // Inject the container into the system under test:
/// @Inject(container: container) var analytics: AnalyticsService
/// ```
@MainActor
@propertyWrapper
public final class Inject<T> {
    // Explicit, nonisolated `deinit` on purpose. Under `defaultIsolation(MainActor)` a class
    // WITHOUT one gets a synthesized *isolated* deinit, which on OS versions older than the
    // toolchain's runtime goes through `swift_task_deinitOnExecutorMainActorBackDeploy`; two
    // of those nested (a ViewModel releasing its Coordinator) aborted with a libmalloc
    // double free on iOS 26.2 (AppStarter CI, Xcode 26.3). Nothing here needs the actor.
    deinit {}

    private var value: T?
    private let container: Container

    public var wrappedValue: T {
        if let value { return value }
        let resolved = container.resolve(T.self)
        value = resolved
        return resolved
    }

    /// Creates a new injected dependency.
    ///
    /// - Parameter container: The container to resolve from. Defaults to `Container.shared`;
    ///   tests pass a child container instead of mutating the global.
    public init(container: Container = .shared) {
        self.container = container
    }
}
