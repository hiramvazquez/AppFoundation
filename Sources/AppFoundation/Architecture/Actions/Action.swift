import Foundation

/// Closure safe to execute on the main actor across concurrency boundaries.
///
/// Use this typealias for callbacks in ViewModels, Views, and other components
/// that need to execute actions on the main thread.
///
/// ## Example
/// ```swift
/// class MyViewModel: ObservableObject {
///     func performAction(onCompleted: Action) {
///         // Do some work...
///         onCompleted()
///     }
/// }
/// ```
public typealias Action = @MainActor @Sendable () -> Void
