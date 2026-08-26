import Foundation

/// Static facade for the global dependency container.
///
/// `Dependency` is a convenience API that delegates to `Container.shared`.
/// Prefer constructor injection. Use `Dependency.resolve()` only in composition roots
/// or when constructor injection is impractical.
///
/// ## Example - Registration
/// ```swift
/// Dependency.register(MyService(), lifecycle: .singleton)
/// ```
///
/// ## Example - Resolution
/// ```swift
/// let service: MyService = Dependency.resolve()
/// ```
///
/// ## Example - Scoped Dependencies
/// ```swift
/// Dependency.createScope("checkout")
/// Dependency.register(CheckoutCart(), lifecycle: .scoped(key: "checkout"))
/// let cart1: CheckoutCart = Dependency.resolve()
/// let cart2: CheckoutCart = Dependency.resolve()  // Same instance as cart1
/// Dependency.destroyScope("checkout")
/// ```
public enum Dependency {
    // MARK: - Registration

    /// Registers a factory closure for a given type with the specified lifecycle.
    ///
    /// - Parameters:
    ///   - factory: Closure that creates instances of type `T`.
    ///   - lifecycle: Determines how the instance is stored and reused.
    ///   - type: The type being registered. Usually inferred automatically.
    public static func register<T>(_ factory: @autoclosure @escaping () -> T,
                                    lifecycle: Lifecycle,
                                    as type: T.Type = T.self) {
        Container.shared.register(factory(), lifecycle: lifecycle, as: type)
    }

    // MARK: - Resolution

    /// Resolves an instance for the provided type.
    ///
    /// Crashes if the type has not been registered. Use `tryResolve(_:)` for safer resolution.
    ///
    /// - Parameter type: The type to resolve. Usually inferred automatically.
    /// - Returns: An instance of the requested type.
    public static func resolve<T>(_ type: T.Type = T.self) -> T {
        Container.shared.resolve(type)
    }

    /// Attempts to resolve an instance for the provided type.
    ///
    /// Returns `nil` if the type has not been registered. This is a safer alternative
    /// to `resolve(_:)` that doesn't crash when a dependency is missing.
    ///
    /// - Parameter type: The type to resolve. Usually inferred automatically.
    /// - Returns: An instance of the requested type, or `nil` if not registered.
    public static func tryResolve<T>(_ type: T.Type = T.self) -> T? {
        Container.shared.tryResolve(type)
    }

    /// Checks if a dependency is registered for the given type.
    ///
    /// - Parameter type: The type to check.
    /// - Returns: `true` if the type is registered, `false` otherwise.
    public static func canResolve<T>(_ type: T.Type) -> Bool {
        Container.shared.canResolve(type)
    }

    // MARK: - Reset

    /// Resets all registered dependencies.
    ///
    /// Use only in tests to start with a clean container.
    public static func reset() {
        Container.shared.reset()
    }

    /// Resets only the given dependency types without affecting the rest.
    ///
    /// Useful for selectively clearing dependencies in tests without a full reset.
    ///
    /// - Parameter types: Array of types to reset.
    public static func resetOnly(_ types: [Any.Type]) {
        Container.shared.resetOnly(types)
    }

    // MARK: - Scope Management

    /// Creates a new scope for scoped dependencies.
    ///
    /// Scopes allow you to share instances within a specific context without making them
    /// global singletons. Useful for feature flows, user sessions, or transaction contexts.
    ///
    /// - Parameter key: Unique identifier for the scope.
    public static func createScope(_ key: String) {
        Container.shared.createScope(key)
    }

    /// Destroys a scope and removes all its cached instances.
    ///
    /// Call this when a flow or feature ends to clean up scoped dependencies.
    ///
    /// - Parameter key: The scope identifier to destroy.
    public static func destroyScope(_ key: String) {
        Container.shared.destroyScope(key)
    }

    /// Checks if a scope exists.
    ///
    /// - Parameter key: The scope identifier to check.
    /// - Returns: `true` if the scope exists, `false` otherwise.
    public static func hasScope(_ key: String) -> Bool {
        Container.shared.hasScope(key)
    }

    #if DEBUG
    /// Validates that all expected dependencies are registered.
    ///
    /// Call this method in DEBUG builds after registering all modules to ensure
    /// all required dependencies are present before the app runs.
    ///
    /// ## Example
    /// ```swift
    /// #if DEBUG
    /// DependencyAssembler.shared.register([...])
    /// Dependency.validateRegistrations([
    ///     APIService.self,
    ///     Coordinator<MainRoute>.self,
    ///     DatabaseService.self
    /// ])
    /// #endif
    /// ```
    ///
    /// - Parameter types: Array of required types to validate.
    public static func validateRegistrations<T>(_ types: [T.Type]) {
        var missing: [String] = []

        for type in types {
            if !canResolve(type) {
                missing.append(String(reflecting: type))
            }
        }

        if !missing.isEmpty {
            let message = """
            Missing Dependencies Detected:
            \(missing.map { "  - \($0)" }.joined(separator: "\n"))

            These dependencies are required but not registered.
            Please register them in your DependencyModule before using.
            """
            logWarning(message, category: "DI")
            assertionFailure(message)
        }
    }

    /// Returns a list of all registered dependency types.
    ///
    /// Useful for debugging dependency configuration issues. Only available in DEBUG builds.
    ///
    /// - Returns: Array of type names that have been registered.
    public static func registeredTypes() -> [String] {
        Container.shared.registeredTypes()
    }
    #endif
}
