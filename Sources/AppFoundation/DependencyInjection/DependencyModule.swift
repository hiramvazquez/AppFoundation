import Foundation

/// Modules that register dependencies with a container.
///
/// Implement `DependencyModule` to create reusable bundles of related dependencies.
/// Each module encapsulates the registration logic for a specific feature or layer;
/// `Container.register(modules:)` assembles them in order at the composition root.
///
/// Modules are `@MainActor`, like `Container`: registration happens at app startup on
/// the main actor, and the factories they register run there too.
///
/// ## Example
/// ```swift
/// struct NetworkModule: DependencyModule {
///     func register(in container: Container) {
///         container.register(APIClient.self) { _ in APIClient() }
///         container.register(NetworkLogger.self) { c in NetworkLogger(client: c.resolve()) }
///     }
/// }
///
/// // At startup:
/// Container.shared.register(modules: [NetworkModule(), RepositoryModule()])
/// ```
@MainActor
public protocol DependencyModule {
    /// Registers dependencies in the provided container.
    ///
    /// - Parameter container: The container to register dependencies with.
    func register(in container: Container)
}

public extension Container {
    /// Registers the provided modules into this container, in order.
    ///
    /// This replaces the old `DependencyAssembler` singleton: an assembler with no state
    /// was ceremony around a loop, and the container is already the single registration
    /// entry point.
    ///
    /// - Parameter modules: Modules to register, applied in array order.
    func register(modules: [DependencyModule]) {
        for module in modules {
            module.register(in: self)
        }
    }
}
