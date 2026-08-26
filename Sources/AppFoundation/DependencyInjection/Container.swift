import Foundation
import os

/// Thread-safe dependency container for registering and resolving instances.
///
/// `Container.shared` is the default global container used by `Dependency` and `@Inject`.
/// In tests, create a fresh `Container()` and assign it to `Container.shared` for isolation.
///
/// ## Lifecycle Management
/// - **Singleton**: Single shared instance for the entire app lifetime.
/// - **Transient**: New instance created on every resolution.
/// - **Scoped**: Shared instance within a named scope (e.g., for a feature flow).
///
/// ## Example - Basic Registration
/// ```swift
/// Container.shared.register(MyService(), lifecycle: .singleton)
/// let service: MyService = Container.shared.resolve()
/// ```
///
/// ## Example - Testing with Fresh Container
/// ```swift
/// func testMyFeature() {
///     let testContainer = Container()
///     Container.shared = testContainer
///     testContainer.register(MockService(), lifecycle: .singleton)
///     // Run tests...
/// }
/// ```
public final class Container: @unchecked Sendable {
    /// The shared global container used by `Dependency` and `@Inject`.
    public static var shared = Container()

    // MARK: - Private Storage

    private var singletons: [String: Any] = [:]
    private var factories: [String: () -> Any] = [:]
    private var scopedInstances: [String: [String: Any]] = [:]
    private var scopedFactories: [String: [String: () -> Any]] = [:]
    private var activeScopes: Set<String> = []
    private let lock = NSLock()

    // MARK: - Initialization

    /// Creates a new dependency container.
    public init() {}

    // MARK: - Registration

    /// Registers a factory closure for a given type with the specified lifecycle.
    ///
    /// In DEBUG builds, registering the same type twice logs a warning and overwrites.
    /// This is intentional to support testing scenarios.
    ///
    /// - Parameters:
    ///   - factory: Closure that creates instances of type `T`.
    ///   - lifecycle: Determines how the instance is stored and reused.
    ///   - type: The type being registered. Usually inferred automatically.
    public func register<T>(_ factory: @autoclosure @escaping () -> T,
                            lifecycle: Lifecycle,
                            as type: T.Type = T.self) {
        let key = String(reflecting: type)

        switch lifecycle {
        case .singleton:
            registerSingleton(key, factory: factory)
        case .transient:
            registerTransient(key, factory: factory)
        case .scoped(let scopeKey):
            registerScoped(key, scopeKey: scopeKey, factory: factory)
        }
    }

    private func registerSingleton<T>(
        _ key: String,
        factory: @escaping () -> T
    ) {
        lock.lock()
        if singletons[key] != nil {
            lock.unlock()
            #if DEBUG
            AppFoundationLogger.di.warning("Re-registering singleton '\(key, privacy: .public)'. Overwriting previous registration.")
            #endif
            lock.lock()
        }
        lock.unlock()

        // Create instance outside lock to avoid deadlocks
        let instance = factory()

        lock.lock()
        singletons[key] = instance
        lock.unlock()
    }

    private func registerTransient<T>(
        _ key: String,
        factory: @escaping () -> T
    ) {
        lock.lock()
        if factories[key] != nil {
            lock.unlock()
            #if DEBUG
            AppFoundationLogger.di.warning("Re-registering transient '\(key, privacy: .public)'. Overwriting previous registration.")
            #endif
            lock.lock()
        }
        factories[key] = factory
        lock.unlock()
    }

    private func registerScoped<T>(
        _ key: String,
        scopeKey: String,
        factory: @escaping () -> T
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard activeScopes.contains(scopeKey) else {
            preconditionFailure("Scope '\(scopeKey)' does not exist. Call Container.createScope(\"\(scopeKey)\") first.")
        }

        if scopedFactories[scopeKey] == nil {
            scopedFactories[scopeKey] = [:]
        }

        if scopedFactories[scopeKey]?[key] != nil {
            #if DEBUG
            AppFoundationLogger.di.warning("Re-registering scoped '\(key, privacy: .public)' in scope '\(scopeKey, privacy: .public)'. Overwriting previous registration.")
            #endif
        }

        scopedFactories[scopeKey]?[key] = factory
    }

    // MARK: - Resolution

    /// Resolves an instance for the provided type.
    ///
    /// Crashes if the type has not been registered. Use `tryResolve(_:)` for safer resolution.
    ///
    /// - Parameter type: The type to resolve. Usually inferred automatically.
    /// - Returns: An instance of the requested type.
    public func resolve<T>(_ type: T.Type = T.self) -> T {
        let key = String(reflecting: type)
        var scopedFactory: (() -> Any)?
        var scopedFactoryKey: String?
        var transientFactory: (() -> Any)?

        lock.lock()

        // 1. Check singletons first
        if let singleton = singletons[key] as? T {
            lock.unlock()
            return singleton
        }

        // 2. Check scoped instances and factories in active scopes
        for scopeKey in activeScopes {
            if let scopedInstance = scopedInstances[scopeKey]?[key] as? T {
                lock.unlock()
                return scopedInstance
            }
            if let factory = scopedFactories[scopeKey]?[key] {
                scopedFactory = factory
                scopedFactoryKey = scopeKey
                break
            }
        }

        // 3. Check transient factories
        transientFactory = factories[key]
        lock.unlock()

        // Resolve scoped factory outside lock
        if let factory = scopedFactory, let scopeKey = scopedFactoryKey,
           let created = factory() as? T {
            lock.lock()
            if let existing = scopedInstances[scopeKey]?[key] as? T {
                lock.unlock()
                return existing
            }
            if activeScopes.contains(scopeKey) {
                if scopedInstances[scopeKey] == nil {
                    scopedInstances[scopeKey] = [:]
                }
                scopedInstances[scopeKey]?[key] = created
            }
            lock.unlock()
            return created
        }

        // Resolve transient factory outside lock
        if let factory = transientFactory, let instance = factory() as? T {
            return instance
        }

        #if DEBUG
        AppFoundationLogger.di.error("Dependency '\(key, privacy: .public)' not registered. Use Container.register() to register this type.")
        fatalError("Dependency '\(key)' not registered. Use Container.register() to register this type.")
        #else
        fatalError("Dependency '\(key)' not registered")
        #endif
    }

    /// Attempts to resolve an instance for the provided type.
    ///
    /// Returns `nil` if the type has not been registered. This is a safer alternative
    /// to `resolve(_:)` that doesn't crash when a dependency is missing.
    ///
    /// - Parameter type: The type to resolve. Usually inferred automatically.
    /// - Returns: An instance of the requested type, or `nil` if not registered.
    public func tryResolve<T>(_ type: T.Type = T.self) -> T? {
        let key = String(reflecting: type)
        var scopedFactory: (() -> Any)?
        var scopedFactoryKey: String?
        var transientFactory: (() -> Any)?

        lock.lock()

        // 1. Check singletons
        if let singleton = singletons[key] as? T {
            lock.unlock()
            return singleton
        }

        // 2. Check scoped instances
        for scopeKey in activeScopes {
            if let scopedInstance = scopedInstances[scopeKey]?[key] as? T {
                lock.unlock()
                return scopedInstance
            }
            if let factory = scopedFactories[scopeKey]?[key] {
                scopedFactory = factory
                scopedFactoryKey = scopeKey
                break
            }
        }

        // 3. Check transient factories
        transientFactory = factories[key]
        lock.unlock()

        if let factory = scopedFactory, let scopeKey = scopedFactoryKey,
           let created = factory() as? T {
            lock.lock()
            if let existing = scopedInstances[scopeKey]?[key] as? T {
                lock.unlock()
                return existing
            }
            if activeScopes.contains(scopeKey) {
                if scopedInstances[scopeKey] == nil {
                    scopedInstances[scopeKey] = [:]
                }
                scopedInstances[scopeKey]?[key] = created
            }
            lock.unlock()
            return created
        }

        if let factory = transientFactory, let instance = factory() as? T {
            return instance
        }

        return nil
    }

    /// Checks if a dependency is registered for the given type.
    ///
    /// - Parameter type: The type to check.
    /// - Returns: `true` if the type is registered, `false` otherwise.
    public func canResolve<T>(_ type: T.Type) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let key = String(reflecting: type)

        if singletons[key] != nil || factories[key] != nil {
            return true
        }

        for scopeKey in activeScopes {
            if scopedInstances[scopeKey]?[key] != nil || scopedFactories[scopeKey]?[key] != nil {
                return true
            }
        }

        return false
    }

    // MARK: - Scope Management

    /// Creates a new scope for scoped dependencies.
    ///
    /// Scopes allow you to share instances within a specific context without making them
    /// global singletons. Useful for feature flows, user sessions, or transaction contexts.
    ///
    /// ## Example
    /// ```swift
    /// Container.shared.createScope("checkout")
    /// Container.shared.register(CheckoutCart(), lifecycle: .scoped(key: "checkout"))
    /// // Use throughout the flow...
    /// Container.shared.destroyScope("checkout")
    /// ```
    ///
    /// - Parameter key: Unique identifier for the scope.
    public func createScope(_ key: String) {
        lock.lock()
        defer { lock.unlock() }

        guard !activeScopes.contains(key) else {
            #if DEBUG
            AppFoundationLogger.di.warning("Scope '\(key, privacy: .public)' already exists.")
            #endif
            return
        }

        activeScopes.insert(key)
        scopedInstances[key] = [:]
        scopedFactories[key] = [:]
    }

    /// Destroys a scope and removes all its cached instances.
    ///
    /// Call this when a flow or feature ends to clean up scoped dependencies.
    ///
    /// - Parameter key: The scope identifier to destroy.
    public func destroyScope(_ key: String) {
        lock.lock()
        defer { lock.unlock() }

        activeScopes.remove(key)
        scopedInstances.removeValue(forKey: key)
        scopedFactories.removeValue(forKey: key)
    }

    /// Checks if a scope exists.
    ///
    /// - Parameter key: The scope identifier to check.
    /// - Returns: `true` if the scope exists, `false` otherwise.
    public func hasScope(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeScopes.contains(key)
    }

    // MARK: - Reset

    /// Resets all registered dependencies.
    ///
    /// Use only in tests to start with a clean container. This removes all singletons,
    /// factories, and scopes.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }

        singletons.removeAll()
        factories.removeAll()
        scopedInstances.removeAll()
        scopedFactories.removeAll()
        activeScopes.removeAll()
    }

    /// Resets only the given dependency types without affecting the rest.
    ///
    /// Useful for selectively clearing dependencies in tests without a full reset.
    ///
    /// - Parameter types: Array of types to reset.
    public func resetOnly(_ types: [Any.Type]) {
        lock.lock()
        defer { lock.unlock() }

        for type in types {
            let key = String(reflecting: type)
            singletons.removeValue(forKey: key)
            factories.removeValue(forKey: key)

            // Also remove from all scopes
            for scopeKey in activeScopes {
                scopedInstances[scopeKey]?.removeValue(forKey: key)
                scopedFactories[scopeKey]?.removeValue(forKey: key)
            }
        }
    }

    #if DEBUG
    /// Returns a list of all registered dependency types.
    ///
    /// Useful for debugging dependency configuration issues. Only available in DEBUG builds.
    ///
    /// - Returns: Array of type names that have been registered.
    public func registeredTypes() -> [String] {
        lock.lock()
        defer { lock.unlock() }

        var allKeys: [String] = []
        allKeys.append(contentsOf: singletons.keys)
        allKeys.append(contentsOf: factories.keys)

        for (_, scopedTypes) in scopedInstances {
            allKeys.append(contentsOf: scopedTypes.keys)
        }
        for (_, scopedTypes) in scopedFactories {
            allKeys.append(contentsOf: scopedTypes.keys)
        }

        return Array(Set(allKeys)).sorted()
    }
    #endif
}
