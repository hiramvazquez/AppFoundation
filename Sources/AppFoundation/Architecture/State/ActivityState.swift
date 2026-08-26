import Foundation

/// Defines how in-progress work is presented to the user.
///
/// This is the ONE activity presentation system: the primary phase
/// (`ViewPhase.loading(style)`) and secondary activity (`ActivityState.loading(style)`)
/// share it. Every style renders something — there is no invisible combination.
///
/// ## Styles
/// - **fullScreen**: opaque cover replacing the content area, blocks interaction
/// - **inline**: small indicator embedded in the layout while content stays visible
/// - **overlay**: dimmed translucent overlay with a spinner above the visible content
public nonisolated enum ActivityStyle: Equatable, Sendable {
    /// Opaque cover replacing the content area; blocks interaction.
    case fullScreen

    /// Small inline indicator inside the screen layout; content stays visible.
    case inline

    /// Dimmed overlay with spinner above the existing content.
    case overlay
}

/// Represents transient work that can happen while the main screen content stays visible.
///
/// Use `ActivityState` for secondary operations such as pull-to-refresh, form submission,
/// pagination, or background sync work. Unlike `ViewPhase.loading`, activity does **not**
/// replace the whole screen state.
///
/// ## Example
/// ```swift
/// performActivity(style: .inline) {
///     try await repository.refresh()
/// }
/// ```
public nonisolated enum ActivityState: Equatable, Sendable {
    /// No secondary work is running.
    case none

    /// Secondary work is running and should be surfaced using the provided style.
    case loading(ActivityStyle)
}
