import Foundation
import os

/// Thread-safe dependency container for registering and resolving instances.
///
/// `Container.shared` is the immutable global container used by `@Inject`. It can never be
/// swapped: tests and previews isolate themselves with **child containers** instead —
/// see `init(parent:)` — or with plain fresh containers passed explicitly.
///
/// ## Lifecycle Management
/// - **Singleton**: single shared instance, created lazily on first resolution.
/// - **Transient**: new instance created on every resolution.
/// - **Scoped**: shared instance within a named scope (e.g. a feature flow).
///
/// ## Example - Basic Registration
/// ```swift
/// Container.shared.register(MyService(), lifecycle: .singleton)
/// let service: MyService = Container.shared.resolve()
/// ```
///
/// ## Example - Testing with a Child Container
/// ```swift
/// @Test func myFeature() {
///     let container = Container(parent: .shared)
///     container.register(MockService(), lifecycle: .singleton, as: Service.self)
///     let sut = MyFeature(container: container)
///     // Registrations in `container` shadow the parent; `Container.shared` is untouched.
/// }
/// ```
///
/// ## Concurrency contract
///
/// The container itself is `nonisolated` and synchronized with `NSLock`, so registration
/// and resolution are safe from any thread **for `Sendable` types**. Factories for
/// `@MainActor`-isolated types (the default in this package's world) are formed on the
/// main actor and are only safe to *execute* there — therefore: resolve main-actor types
/// from main-actor code (`@Inject` already guarantees this). Resolving a main-actor type
/// from a background thread is a programmer error the type system cannot express through
/// an `Any`-typed store; the contract is documented here instead.
///
/// - Note: `@unchecked Sendable` justification (C3): every access to mutable state goes
///   through `lock`. An `actor` would force `await` on resolution and `@Inject` requires
///   synchronous access from property getters; `Mutex` (Synchronization) requires iOS 18
///   and this package supports iOS 17. `NSLock` + single-class encapsulation is the
///   remaining correct tool. Revisit when the minimum target reaches iOS 18.
public nonisolated final class Container: @unchecked Sendable {
    /// The shared global container used by `@Inject`.
    ///
    /// Immutable on purpose: a swappable global is shared mutable state that every test
    /// can corrupt for every other test. Use child containers for overrides.
    public static let shared = Container()

    // MARK: - Private Storage

    /// Optional parent for fallback resolution (child containers shadow the parent).
    private let parent: Container?

    /// Lazily-created singleton instances, by type key. Created on first resolution (C5).
    private var singletons: [String: Any] = [:]

    /// Pending singleton factories, consumed on first resolution.
    private var singletonFactories: [String: () -> Any] = [:]

    /// Transient factories, executed on every resolution.
    private var transientFactories: [String: () -> Any] = [:]

    private var scopedInstances: [String: [String: Any]] = [:]
    private var scopedFactories: [String: [String: () -> Any]] = [:]

    /// Active scopes in creation order (C6): resolution walks them from the most recently
    /// created to the oldest, so shadowing between scopes is deterministic — the newest
    /// scope wins. A `Set` here made resolution order random.
    private var activeScopes: [String] = []

    private let lock = NSLock()

    // MARK: - Initialization

    /// Creates a new dependency container.
    ///
    /// - Parameter parent: Optional parent container. Types not registered here are
    ///   resolved against the parent (and so on up the chain). Registrations in a child
    ///   shadow the parent without mutating it — this is the override mechanism for tests,
    ///   previews, and feature-level composition.
    public init(parent: Container? = nil) {
        self.parent = parent
    }

    // MARK: - Registration

    /// Registers a factory for a given type with the specified lifecycle.
    ///
    /// This is the **single** public registration path. Singleton factories run lazily on
    /// first resolution (C5) — if construction order matters, resolve eagerly right after
    /// registering.
    ///
    /// In DEBUG builds, registering the same type twice logs a warning and overwrites.
    /// This is intentional to support preview/test overrides in child containers.
    ///
    /// - Parameters:
    ///   - factory: Autoclosure that creates instances of type `T`.
    ///   - lifecycle: Determines how instances are stored and reused.
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

    private func registerSingleton<T>(_ key: String, factory: @escaping () -> T) {
        lock.lock()
        defer { lock.unlock() }

        if singletons[key] != nil || singletonFactories[key] != nil {
            #if DEBUG
            AppFoundationLogger.di.warning("Re-registering singleton '\(key, privacy: .public)'. Overwriting previous registration.")
            #endif
            singletons.removeValue(forKey: key)
        }
        singletonFactories[key] = factory
    }

    private func registerTransient<T>(_ key: String, factory: @escaping () -> T) {
        lock.lock()
        defer { lock.unlock() }

        if transientFactories[key] != nil {
            #if DEBUG
            AppFoundationLogger.di.warning("Re-registering transient '\(key, privacy: .public)'. Overwriting previous registration.")
            #endif
        }
        transientFactories[key] = factory
    }

    private func registerScoped<T>(_ key: String, scopeKey: String, factory: @escaping () -> T) {
        lock.lock()
        defer { lock.unlock() }

        guard activeScopes.contains(scopeKey) else {
            preconditionFailure("Scope '\(scopeKey)' does not exist. Call createScope(\"\(scopeKey)\") first.")
        }

        if scopedFactories[scopeKey]?[key] != nil {
            #if DEBUG
            AppFoundationLogger.di.warning("Re-registering scoped '\(key, privacy: .public)' in scope '\(scopeKey, privacy: .public)'. Overwriting previous registration.")
            #endif
        }

        scopedFactories[scopeKey]?[key] = factory
        scopedInstances[scopeKey]?.removeValue(forKey: key)
    }

    // MARK: - Resolution

    /// Resolves an instance for the provided type.
    ///
    /// Precondition: the type (or its key in a parent container) must be registered —
    /// resolving an unregistered type is a programmer error and traps. Use `tryResolve(_:)`
    /// when absence is a recoverable state.
    ///
    /// - Parameter type: The type to resolve. Usually inferred automatically.
    /// - Returns: An instance of the requested type.
    public func resolve<T>(_ type: T.Type = T.self) -> T {
        if let instance = tryResolve(type) {
            return instance
        }
        let key = String(reflecting: type)
        AppFoundationLogger.di.error("Dependency '\(key, privacy: .public)' not registered. Use Container.register() to register this type.")
        fatalError("Dependency '\(key)' not registered. Use Container.register() to register this type.")
    }

    /// Attempts to resolve an instance for the provided type.
    ///
    /// Resolution order is deterministic: singletons, then scoped registrations from the
    /// most recently created scope to the oldest (C6), then transients — and only if
    /// nothing matched, the parent chain.
    ///
    /// - Parameter type: The type to resolve. Usually inferred automatically.
    /// - Returns: An instance of the requested type, or `nil` if not registered.
    public func tryResolve<T>(_ type: T.Type = T.self) -> T? {
        let key = String(reflecting: type)

        if let resolved: T = resolveLocally(key) {
            return resolved
        }
        return parent?.tryResolve(type)
    }

    private func resolveLocally<T>(_ key: String) -> T? {
        var scopedFactory: (() -> Any)?
        var scopedFactoryKey: String?

        lock.lock()

        // 1. Existing singleton instance.
        if let singleton = singletons[key] as? T {
            lock.unlock()
            return singleton
        }

        // 2. Pending singleton factory → lazy creation with correct double-checked
        //    locking (C4): the factory runs OUTSIDE the lock (it may resolve its own
        //    dependencies against this container — running it under the lock would
        //    deadlock), and the first stored instance wins if two threads race.
        if let factory = singletonFactories[key] {
            lock.unlock()
            let created = factory()

            lock.lock()
            if let winner = singletons[key] as? T {
                // Another thread finished first; discard our instance.
                lock.unlock()
                return winner
            }
            singletons[key] = created
            singletonFactories.removeValue(forKey: key)
            lock.unlock()
            return created as? T
        }

        // 3. Scoped: newest scope wins (C6).
        for scopeKey in activeScopes.reversed() {
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

        // 4. Transient factory.
        let transientFactory = transientFactories[key]
        lock.unlock()

        // Scoped creation outside the lock, same double-checked pattern as singletons.
        if let factory = scopedFactory, let scopeKey = scopedFactoryKey {
            let created = factory()

            lock.lock()
            if let winner = scopedInstances[scopeKey]?[key] as? T {
                lock.unlock()
                return winner
            }
            if activeScopes.contains(scopeKey) {
                scopedInstances[scopeKey]?[key] = created
            }
            lock.unlock()
            return created as? T
        }

        if let factory = transientFactory {
            return factory() as? T
        }

        return nil
    }

    /// Checks if a dependency is registered for the given type, here or in a parent.
    ///
    /// - Parameter type: The type to check.
    /// - Returns: `true` if the type is registered, `false` otherwise.
    public func canResolve<T>(_ type: T.Type) -> Bool {
        let key = String(reflecting: type)

        lock.lock()
        var found = singletons[key] != nil
            || singletonFactories[key] != nil
            || transientFactories[key] != nil

        if !found {
            for scopeKey in activeScopes {
                if scopedInstances[scopeKey]?[key] != nil || scopedFactories[scopeKey]?[key] != nil {
                    found = true
                    break
                }
            }
        }
        lock.unlock()

        return found || (parent?.canResolve(type) ?? false)
    }

    // MARK: - Scope Management

    /// Creates a new scope for scoped dependencies.
    ///
    /// Scopes allow you to share instances within a specific context without making them
    /// global singletons. Useful for feature flows, user sessions, or transaction contexts.
    /// When several scopes register the same type, the most recently created scope wins.
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

        activeScopes.append(key)
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

        activeScopes.removeAll { $0 == key }
        scopedInstances.removeValue(forKey: key)
        scopedFactories.removeValue(forKey: key)
    }

    /// Checks if a scope exists in this container (parents are not consulted).
    ///
    /// - Parameter key: The scope identifier to check.
    /// - Returns: `true` if the scope exists, `false` otherwise.
    public func hasScope(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeScopes.contains(key)
    }

    // MARK: - Reset

    /// Resets all registered dependencies in this container (the parent is untouched).
    ///
    /// Intended for tests working with their own containers.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }

        singletons.removeAll()
        singletonFactories.removeAll()
        transientFactories.removeAll()
        scopedInstances.removeAll()
        scopedFactories.removeAll()
        activeScopes.removeAll()
    }

    /// Resets only the given dependency types without affecting the rest.
    ///
    /// - Parameter types: Array of types to reset.
    public func resetOnly(_ types: [Any.Type]) {
        lock.lock()
        defer { lock.unlock() }

        for type in types {
            let key = String(reflecting: type)
            singletons.removeValue(forKey: key)
            singletonFactories.removeValue(forKey: key)
            transientFactories.removeValue(forKey: key)

            for scopeKey in activeScopes {
                scopedInstances[scopeKey]?.removeValue(forKey: key)
                scopedFactories[scopeKey]?.removeValue(forKey: key)
            }
        }
    }

    #if DEBUG
    /// Returns a list of all dependency types registered in this container
    /// (parents are not included).
    ///
    /// Useful for debugging dependency configuration issues. Only available in DEBUG builds.
    ///
    /// - Returns: Array of type names that have been registered.
    public func registeredTypes() -> [String] {
        lock.lock()
        defer { lock.unlock() }

        var allKeys: [String] = []
        allKeys.append(contentsOf: singletons.keys)
        allKeys.append(contentsOf: singletonFactories.keys)
        allKeys.append(contentsOf: transientFactories.keys)

        for (_, scopedTypes) in scopedInstances {
            allKeys.append(contentsOf: scopedTypes.keys)
        }
        for (_, scopedTypes) in scopedFactories {
            allKeys.append(contentsOf: scopedTypes.keys)
        }

        return Array(Set(allKeys)).sorted()
    }

    /// Validates that all expected dependencies are registered (here or in a parent).
    ///
    /// Call after registering all modules to ensure required dependencies are present
    /// before the app runs. Only available in DEBUG builds.
    ///
    /// - Parameter types: Array of required types to validate.
    public func validateRegistrations(_ types: [Any.Type]) {
        let missing = types
            .filter { !canResolveErased($0) }
            .map { String(reflecting: $0) }

        if !missing.isEmpty {
            let message = """
            Missing Dependencies Detected:
            \(missing.map { "  - \($0)" }.joined(separator: "\n"))

            These dependencies are required but not registered.
            Please register them in your DependencyModule before using.
            """
            AppFoundationLogger.di.warning("\(message, privacy: .public)")
            assertionFailure(message)
        }
    }

    private func canResolveErased(_ type: Any.Type) -> Bool {
        let key = String(reflecting: type)

        lock.lock()
        var found = singletons[key] != nil
            || singletonFactories[key] != nil
            || transientFactories[key] != nil
        if !found {
            for scopeKey in activeScopes {
                if scopedInstances[scopeKey]?[key] != nil || scopedFactories[scopeKey]?[key] != nil {
                    found = true
                    break
                }
            }
        }
        lock.unlock()

        return found || (parent?.canResolveErased(type) ?? false)
    }
    #endif
}
