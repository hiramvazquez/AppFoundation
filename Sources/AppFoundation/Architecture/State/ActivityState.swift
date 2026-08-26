import Foundation

/// Represents transient work that can happen while the main screen content stays visible.
///
/// Use `ActivityState` for secondary operations such as pull-to-refresh, form submission,
/// pagination, or background sync work. Unlike `ViewPhase.loading`, activity does **not**
/// replace the whole screen state.
///
/// ## Example
/// ```swift
/// startActivity(.overlay)
/// defer { stopActivity() }
/// try await repository.refresh()
/// ```
public nonisolated enum ActivityState: Equatable, Sendable {
    /// No secondary work is running.
    case none

    /// Secondary work is running and should be surfaced using the provided style.
    case loading(ActivityStyle)
}

/// Defines how secondary activity should be shown while content remains visible.
public nonisolated enum ActivityStyle: Equatable, Sendable {
    /// Small inline indicator inside the screen layout.
    case inline

    /// Overlay spinner above the existing content.
    case overlay
}
