//
//  DeepLink.swift
//  AppFoundation
//
//  Deep link system connected to Coordinator (A12): parse a URL into a typed link,
//  map it to a navigation action, and let the coordinator apply it.
//

import Foundation

/// Protocol for defining deep link types in your app.
///
/// Implement this protocol to define the deep link cases your app supports.
///
/// ## Example
/// ```swift
/// enum AppDeepLink: DeepLinkType {
///     case notifications
///     case profile(userId: String)
///
///     static func parse(_ url: URL) -> AppDeepLink? {
///         let components = url.pathComponents
///         if components.contains("notifications") { return .notifications }
///         if let index = components.firstIndex(of: "profile"), components.count > index + 1 {
///             return .profile(userId: components[index + 1])
///         }
///         return nil
///     }
/// }
/// ```
public nonisolated protocol DeepLinkType {
    /// Parse a URL into a deep link case
    static func parse(_ url: URL) -> Self?
}

/// A navigation command produced from a deep link.
///
/// The mapping from a parsed link to routes belongs to the app (only it knows its
/// route graph); applying the command belongs to the coordinator.
public nonisolated enum DeepLinkAction<Route: Hashable>: Equatable {
    /// Replace the main stack path with `routes`, dismissing any modal first —
    /// "open the app at this exact place".
    case setStack([Route])

    /// Push a route onto the currently active stack.
    case push(Route)

    /// Present a route modally.
    case present(Route, style: PresentationStyle)
}

public extension Coordinator {
    /// Applies a deep-link navigation action.
    ///
    /// `.setStack` dismisses any presented modal before replacing the main path: a deep
    /// link that says "go here" owns the resulting navigation state.
    func handle(_ action: DeepLinkAction<Route>) {
        switch action {
        case .setStack(let routes):
            dismiss()
            setStack(routes)
        case .push(let route):
            push(route)
        case .present(let route, let style):
            present(route, as: style)
        }
    }

    /// Parses `url` as `Link` and applies the action `map` produces for it.
    ///
    /// - Parameters:
    ///   - url: The incoming URL (universal link, custom scheme, ...).
    ///   - linkType: The app's `DeepLinkType` implementation.
    ///   - map: Maps a parsed link to a navigation action; return `nil` to ignore it.
    /// - Returns: `true` when the URL was parsed and its action applied.
    ///
    /// ## Example
    /// ```swift
    /// .onOpenURL { url in
    ///     coordinator.handle(url, as: AppDeepLink.self) { link in
    ///         switch link {
    ///         case .notifications: .setStack([.notifications])
    ///         case .profile(let id): .push(.profile(userId: id))
    ///         }
    ///     }
    /// }
    /// ```
    @discardableResult
    func handle<Link: DeepLinkType>(
        _ url: URL,
        as linkType: Link.Type,
        map: (Link) -> DeepLinkAction<Route>?
    ) -> Bool {
        guard let link = Link.parse(url), let action = map(link) else {
            return false
        }
        handle(action)
        return true
    }
}
