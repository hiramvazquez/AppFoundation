import Foundation

/// Modules that register dependencies with a container.
///
/// Implement `DependencyModule` to create reusable bundles of related dependencies.
/// Each module encapsulates the registration logic for a specific feature or layer.
///
/// ## Example
/// ```swift
/// @MainActor
/// final class NetworkModule: DependencyModule {
///     func register(in container: Container) {
///         container.register(APIClient(), lifecycle: .singleton)
///         container.register(NetworkLogger(), lifecycle: .singleton)
///     }
/// }
///
/// @MainActor
/// final class RepositoryModule: DependencyModule {
///     func register(in container: Container) {
///         let client: APIClient = container.resolve()
///         container.register(UserRepository(client: client), lifecycle: .singleton)
///     }
/// }
/// ```
@MainActor
public protocol DependencyModule {
    /// Registers dependencies in the provided container.
    ///
    /// - Parameter container: The container to register dependencies with.
    func register(in container: Container)
}

// MARK: - Backward Compatibility Extension

public extension DependencyModule {
    /// Registers dependencies into the shared container.
    ///
    /// This convenience method uses `Container.shared` by default.
    /// Prefer `register(in container:)` for better testability.
    func register() {
        register(in: .shared)
    }
}

// MARK: - Dependency Assembler

/// Assembles and registers groups of dependency modules.
///
/// `DependencyAssembler` orchestrates the registration of multiple modules,
/// allowing you to modularize your dependency configuration across features.
///
/// ## Example
/// ```swift
/// func setupDependencies() {
///     DependencyAssembler.shared.register([
///         NetworkModule(),
///         RepositoryModule(),
///         ViewModelModule(),
///     ])
/// }
/// ```
@MainActor
public final class DependencyAssembler {
    /// The shared global assembler instance.
    public static let shared = DependencyAssembler()

    private init() {}

    /// Registers the provided modules with a container.
    ///
    /// - Parameters:
    ///   - modules: Array of modules to register.
    ///   - container: The container to register into. Defaults to `Container.shared`.
    public func register(_ modules: [DependencyModule], in container: Container = .shared) {
        modules.forEach { $0.register(in: container) }
    }
}
