import Foundation

/// Determines how a dependency is stored and resolved.
///
/// There is no "scoped" lifecycle: a dependency shared by one flow (checkout, session) is a
/// `.singleton` registered in a **child container** owned by that flow — see
/// `Container.init(parent:)`. The flow ends when its container is released.
public nonisolated enum Lifecycle: Equatable, Sendable {
    /// One instance per container, created lazily on first resolution.
    ///
    /// In `Container.shared` that means the app lifetime: networking, logging, storage,
    /// app-level preferences. In a child container it means the lifetime of that flow.
    case singleton

    /// New instance created on every resolution.
    ///
    /// Use for stateful objects like view models that must not be shared between screens.
    case transient
}
