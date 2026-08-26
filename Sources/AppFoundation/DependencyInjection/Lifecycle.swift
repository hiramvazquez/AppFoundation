import Foundation

/// Determines how a dependency is stored and resolved.
///
/// ## Cases
/// - `singleton`: Single shared instance for the app lifetime. Expensive-to-create objects should be singletons.
/// - `transient`: New instance created on every resolution. Stateful objects (ViewModels) are typically transient.
/// - `scoped(key:)`: Shared instance within a named scope. Useful for feature flows or user sessions.
public enum Lifecycle: Equatable, Sendable {
    /// Single shared instance for the entire app lifetime.
    ///
    /// Use for stateless services like networking, logging, database, or app-level preferences.
    case singleton

    /// New instance created on every resolution.
    ///
    /// Use for stateful objects like ViewModels that should not be shared between screens.
    case transient

    /// Shared instance within a named scope.
    ///
    /// Use for dependencies that should outlive a single screen but not the entire app.
    /// Common uses: checkout flows, user sessions, feature module state.
    case scoped(key: String)
}
