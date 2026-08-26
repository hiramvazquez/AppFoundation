import Foundation

/// Property wrapper that lazily resolves a dependency from the global container.
///
/// `@Inject` resolves dependencies on first access and caches the result.
/// Prefer constructor injection. Use `@Inject` only when constructor injection
/// is impractical (e.g., in Views or leaf objects).
///
/// ## Example - Basic Usage
/// ```swift
/// class MyViewModel: ObservableObject {
///     @Inject private var analytics: AnalyticsService
///
///     func trackEvent() {
///         analytics.log("event_name")
///     }
/// }
/// ```
///
/// ## Example - Optional Dependency
/// ```swift
/// class MyView: View {
///     @Inject private var themeService: ThemeService?
///
///     var body: some View {
///         Text("Hello").foregroundColor(themeService?.accentColor ?? .blue)
///     }
/// }
/// ```
@propertyWrapper
public final class Inject<T> {
    private var value: T?

    public var wrappedValue: T {
        if let value { return value }
        let resolved = Container.shared.resolve(T.self)
        value = resolved
        return resolved
    }

    /// Creates a new injected dependency.
    public init() {}
}
