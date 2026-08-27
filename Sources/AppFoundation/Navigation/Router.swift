import Foundation

// MARK: - Router Protocol

/// Protocol that abstracts navigation commands.
///
/// `Router` is the primary interface that ViewModels depend on for navigation,
/// decoupling them from the concrete `Coordinator` type. This allows for easier
/// testing and flexible navigation implementations.
///
/// Implementations like `Coordinator` conform to this protocol and handle the
/// actual navigation state management.
///
/// ## Example
/// ```swift
/// @Observable
/// final class MyViewModel {
///     let router: any Router<AppRoute>
///
///     func navigateToDetail() {
///         router.push(.detail(id: 123))
///     }
/// }
/// ```
@MainActor
public protocol Router<Route>: AnyObject {
    /// The route type this router handles.
    associatedtype Route: Hashable

    /// Push a route onto the active navigation stack.
    /// - Parameter route: The route to push.
    func push(_ route: Route)

    /// Pop the current route from the active navigation stack.
    func pop()

    /// Pop all routes and return to the root view.
    func popToRoot()

    /// Pop routes until reaching a specific route (inclusive).
    /// - Parameter route: The route to pop back to.
    func popTo(_ route: Route)

    /// Present a route modally using the specified presentation style.
    /// - Parameters:
    ///   - route: The route to present.
    ///   - style: How to present the route (sheet or fullScreenCover).
    func present(_ route: Route, as style: PresentationStyle)

    /// Dismiss the active modal presentation.
    func dismiss()
}

// MARK: - PresentationStyle

/// Defines how a route should be presented modally.
public nonisolated enum PresentationStyle: Equatable, Sendable {
    /// Present as a sheet (modal with partial overlay).
    case sheet

    /// Present as a full screen cover (opaque modal).
    case fullScreenCover
}
