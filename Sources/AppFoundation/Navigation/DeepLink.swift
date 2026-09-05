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
    ///
    /// The most destructive of the three: it discards whatever the user had open and owns
    /// the resulting navigation state outright. Never return this for a route that assumes a
    /// signed-in user without checking the session first — see the security note on
    /// `Coordinator.handle(_:as:map:)`.
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
    /// - Important: Security boundary. `url` is untrusted input from outside your process —
    ///   a universal link, a custom URL scheme, a push notification payload, or a link
    ///   another app opened. This package has no permission system and can't know which of
    ///   your routes are sensitive, so `map` is the ONLY place this call gives you to reject
    ///   or redirect a link before it reaches navigation state. Validate there, not in the
    ///   destination view:
    ///   - **Gate authenticated routes before returning an action**, never after. If the
    ///     route you're about to return assumes a signed-in user, check your session first:
    ///     ```swift
    ///     coordinator.handle(url, as: AppDeepLink.self) { link in
    ///         switch link {
    ///         case .profile(let id):
    ///             guard session.isAuthenticated else {
    ///                 return .setStack([.login])   // or `nil` to ignore the link entirely
    ///             }
    ///             return .push(.profile(userId: id))
    ///         }
    ///     }
    ///     ```
    ///     Don't rely on the destination screen to check for you — `.setStack` (below)
    ///     replaces the whole navigation stack, so a link mapped without this guard can
    ///     jump straight past login/onboarding.
    ///   - **Treat parameters `Link.parse` extracted from the URL as attacker-controlled.**
    ///     An id, a token, a query value — validate/sanitize in `map` before it becomes part
    ///     of a `Route`, the same way you'd treat any external input.
    ///   - There's no hook here beyond `map` on purpose: `map` already runs synchronously
    ///     with full closure capture, so it can already read whatever session/auth state
    ///     your app injects and reject or rewrite the action — an extra parameter for this
    ///     would only wrap the `guard` above in ceremony, not add anything it can't already
    ///     do.
    ///
    /// - Parameters:
    ///   - url: The incoming URL (universal link, custom scheme, ...).
    ///   - linkType: The app's `DeepLinkType` implementation.
    ///   - map: Maps a parsed link to a navigation action; return `nil` to ignore it. This is
    ///     where you validate — see above.
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
