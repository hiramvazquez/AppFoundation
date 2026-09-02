import Foundation
import os

/// Main-actor dependency container: the app's composition root.
///
/// `Container.shared` is the immutable global container used by `@Inject`. It can never be
/// swapped: tests, previews and feature flows isolate themselves with **child containers**
/// (`init(parent:)`) or with plain fresh containers passed explicitly.
///
/// ## Isolation
///
/// The container is `@MainActor`. Everything that registers or resolves in this package
/// already lives there (`DependencyModule`, `@Inject`, view models, views), so there is no
/// mutex, no double-checked locking and no unchecked `Sendable` conformance: the compiler
/// guarantees that factories for main-actor types run on the main actor. Code that is `nonisolated`
/// does not resolve — it receives its dependencies already resolved through its
/// initializer, which is constructor injection, the first rule of the README.
///
/// ## Lifecycle
///
/// - `.singleton`: one instance per container, created lazily on first resolution.
/// - `.transient`: a new instance on every resolution.
///
/// A dependency that should outlive a screen but not the app (a checkout, a session) is a
/// singleton **in a child container** owned by that flow: when the flow releases its
/// container, the instances go with it. There is no named scope to create or destroy.
///
/// ## Factories receive a container
///
/// A factory resolves its own dependencies from the container it was registered in
/// (`self`), which falls back to its parent chain. Registering a factory in a parent and
/// overriding one of its dependencies in a child does **not** change what the parent's
/// singleton sees — that is what keeps `Container.shared` free of test doubles.
///
/// ## Example
/// ```swift
/// Container.shared.register(ProfileRepository.self) { _ in LiveProfileRepository() }
/// Container.shared.register(ProfileViewModel.self, lifecycle: .transient) { c in
///     ProfileViewModel(repository: c.resolve())
/// }
/// let viewModel: ProfileViewModel = Container.shared.resolve()
/// ```
///
/// ## Example - Testing with a Child Container
/// ```swift
/// @Test func myFeature() {
///     let container = Container(parent: .shared)
///     container.register(instance: MockService(), as: Service.self)
///     let sut = MyFeature(container: container)
///     // Registrations in `container` shadow the parent; `Container.shared` is untouched.
/// }
/// ```
///
/// ## Cycles
///
/// A factory that (transitively) resolves the type it is building — A → B → A — would
/// recurse forever. The container detects it and traps with a message naming every type
/// in the cycle. Break it by passing one side through its initializer.
@MainActor
public final class Container {
    /// The shared global container used by `@Inject`.
    ///
    /// Immutable on purpose: a swappable global is shared mutable state that every test
    /// can corrupt for every other test. Use child containers for overrides.
    public static let shared = Container()

    // MARK: - Private Storage

    private struct Registration {
        let typeName: String
        let lifecycle: Lifecycle
        let factory: @MainActor (Container) -> Any
    }

    /// Optional parent for fallback resolution (child containers shadow the parent).
    private let parent: Container?

    /// Registrations by type identity.
    private var registrations: [ObjectIdentifier: Registration] = [:]

    /// Lazily-created singleton instances, by type identity.
    private var singletons: [ObjectIdentifier: Any] = [:]

    /// Reentrancy guard: the types whose factories are currently running.
    private var resolutionStack = ResolutionStack()

    /// Whether a factory is currently running. Internal: lets tests check the guard unwinds.
    var isResolving: Bool { !resolutionStack.isEmpty }

    // MARK: - Initialization

    /// Creates a new dependency container.
    ///
    /// - Parameter parent: Optional parent container. Types not registered here are
    ///   resolved against the parent (and so on up the chain). Registrations in a child
    ///   shadow the parent without mutating it — this is the override mechanism for tests,
    ///   previews, and per-flow composition.
    public init(parent: Container? = nil) {
        self.parent = parent
    }

    // MARK: - Registration

    /// Registers a factory for `type` with the given lifecycle.
    ///
    /// Singleton factories run lazily on first resolution — if construction order matters,
    /// resolve eagerly right after registering. The factory receives the container it was
    /// registered in, so it can resolve its own dependencies without touching a global.
    ///
    /// Registering the same type twice overwrites (and drops any cached singleton). In
    /// DEBUG builds this logs a warning; it is intentional so child containers can
    /// override for previews and tests.
    ///
    /// - Parameters:
    ///   - type: The type being registered. Usually inferred from the factory's return.
    ///   - lifecycle: How instances are stored and reused. Defaults to `.singleton`.
    ///   - factory: Builds an instance of `T`; receives the registering container.
    public func register<T>(
        _ type: T.Type = T.self,
        lifecycle: Lifecycle = .singleton,
        factory: @escaping @MainActor (Container) -> T
    ) {
        store(Registration(typeName: String(reflecting: type), lifecycle: lifecycle, factory: factory),
              for: ObjectIdentifier(type))
    }

    /// Registers an already-built instance as a singleton for `type`.
    ///
    /// The honest spelling of "this object, as this protocol": there is no factory and
    /// nothing is deferred.
    ///
    /// - Parameters:
    ///   - instance: The instance to hand out on every resolution.
    ///   - type: The type to register it as. Defaults to the instance's static type; pass
    ///     a protocol to register it as an abstraction.
    public func register<T>(instance: T, as type: T.Type = T.self) {
        let key = ObjectIdentifier(type)
        store(Registration(typeName: String(reflecting: type), lifecycle: .singleton, factory: { _ in instance }),
              for: key)
        singletons[key] = instance
    }

    private func store(_ registration: Registration, for key: ObjectIdentifier) {
        if registrations[key] != nil {
            #if DEBUG
            AppFoundationLogger.di.warning("Re-registering '\(registration.typeName, privacy: .public)'. Overwriting previous registration.")
            #endif
            singletons.removeValue(forKey: key)
        }
        registrations[key] = registration
    }

    // MARK: - Resolution

    /// Resolves an instance for the provided type.
    ///
    /// Precondition: the type must be registered here or in a parent — resolving an
    /// unregistered type is a programmer error and traps. Use `tryResolve(_:)` when
    /// absence is a recoverable state.
    ///
    /// - Parameter type: The type to resolve. Usually inferred automatically.
    /// - Returns: An instance of the requested type.
    public func resolve<T>(_ type: T.Type = T.self) -> T {
        if let instance = tryResolve(type) {
            return instance
        }
        let name = String(reflecting: type)
        AppFoundationLogger.di.error("Dependency '\(name, privacy: .public)' not registered. Use Container.register() to register this type.")
        preconditionFailure("Dependency '\(name)' not registered. Use Container.register() to register this type.")
    }

    /// Attempts to resolve an instance for the provided type.
    ///
    /// Resolution order: this container (cached singleton, then its registration), and
    /// only if nothing matched, the parent chain.
    ///
    /// - Parameter type: The type to resolve. Usually inferred automatically.
    /// - Returns: An instance of the requested type, or `nil` if not registered.
    public func tryResolve<T>(_ type: T.Type = T.self) -> T? {
        let key = ObjectIdentifier(type)

        if let cached = singletons[key] as? T {
            return cached
        }
        guard let registration = registrations[key] else {
            return parent?.tryResolve(type)
        }

        if let cycle = resolutionStack.push(key, name: registration.typeName) {
            AppFoundationLogger.di.error("\(cycle, privacy: .public)")
            preconditionFailure(cycle)
        }
        defer { resolutionStack.pop() }

        let created = registration.factory(self)
        if registration.lifecycle == .singleton {
            singletons[key] = created
        }
        return created as? T
    }

    /// Checks if a dependency is registered for the given type, here or in a parent.
    ///
    /// - Parameter type: The type to check.
    /// - Returns: `true` if the type is registered, `false` otherwise.
    public func canResolve<T>(_ type: T.Type) -> Bool {
        canResolve(erased: type)
    }

    private func canResolve(erased type: Any.Type) -> Bool {
        registrations[ObjectIdentifier(type)] != nil || (parent?.canResolve(erased: type) ?? false)
    }

    // MARK: - Reset

    /// Removes every registration and cached instance in this container (the parent is
    /// untouched).
    ///
    /// Intended for tests working with their own containers.
    public func reset() {
        registrations.removeAll()
        singletons.removeAll()
    }

    #if DEBUG
    /// Returns the names of all dependency types registered in this container
    /// (parents are not included). Sorted, for stable diagnostics.
    ///
    /// Only available in DEBUG builds.
    public func registeredTypes() -> [String] {
        registrations.values.map(\.typeName).sorted()
    }

    /// Validates that all expected dependencies are registered (here or in a parent).
    ///
    /// Call after registering all modules to ensure required dependencies are present
    /// before the app runs. Only available in DEBUG builds.
    ///
    /// - Parameter types: Array of required types to validate.
    public func validateRegistrations(_ types: [Any.Type]) {
        let missing = types
            .filter { !canResolve(erased: $0) }
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
    #endif
}

// MARK: - ResolutionStack

/// Reentrancy guard for factory execution: detects A → B → A cycles between factories.
///
/// Kept separate from `Container` so the detection itself is testable — the container's
/// only reaction to a detected cycle is to trap, and traps cannot be asserted in tests.
struct ResolutionStack {
    private var entries: [(key: ObjectIdentifier, name: String)] = []

    /// Whether any factory is currently running.
    var isEmpty: Bool { entries.isEmpty }

    /// Pushes `key` before running its factory.
    ///
    /// - Returns: `nil` when the push is legitimate; otherwise a message naming every type
    ///   in the cycle, starting and ending with `name`.
    mutating func push(_ key: ObjectIdentifier, name: String) -> String? {
        if let start = entries.firstIndex(where: { $0.key == key }) {
            let chain = (entries[start...].map(\.name) + [name]).joined(separator: " → ")
            return """
            Dependency cycle detected while resolving '\(name)': \(chain). \
            Factories must not resolve each other; pass one side through its initializer instead.
            """
        }
        entries.append((key, name))
        return nil
    }

    /// Pops the most recently pushed type after its factory finished.
    mutating func pop() {
        _ = entries.popLast()
    }
}
