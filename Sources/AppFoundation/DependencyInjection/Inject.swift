import Foundation

/// Property wrapper that lazily resolves a dependency from a container.
///
/// `@Inject` resolves on first access and caches the result. Prefer constructor
/// injection; use `@Inject` only when constructor injection is impractical
/// (e.g. in Views or leaf objects).
///
/// ## Isolation (decided under MainActor-by-default)
///
/// `Inject` is `@MainActor`: views, view models, and most app code live there, and the
/// cached `value` needs isolation anyway. For `nonisolated` types that need a dependency
/// off the main actor, call `Container.resolve()` explicitly — the container itself is
/// thread-safe for `Sendable` types.
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
/// final class ProfileViewModel: BaseViewModel {
///     @Inject private var analytics: AnalyticsService
///
///     func trackEvent() {
///         analytics.log("event_name")
///     }
/// }
/// ```
///
/// ## Example - Overriding in Tests
/// ```swift
/// let container = Container(parent: .shared)
/// container.register(MockAnalytics(), lifecycle: .singleton, as: AnalyticsService.self)
/// // Inject the container into the system under test:
/// @Inject(container: container) var analytics: AnalyticsService
/// ```
@MainActor
@propertyWrapper
public final class Inject<T> {
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
